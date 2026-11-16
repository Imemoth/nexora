#include "desktop_integration.h"

#include <flutter/standard_method_codec.h>

#include <algorithm>
#include <cstdint>
#include <cstring>
#include <string>
#include <variant>
#include <vector>

#include "resource.h"

namespace {

constexpr UINT kTrayMessage = WM_APP + 1;
constexpr UINT kHideMessage = WM_APP + 2;
constexpr UINT kTrayIconId = 1;
constexpr UINT kMenuOpen = 1001;
constexpr UINT kMenuExit = 1002;
constexpr UINT_PTR kBalloonGuardTimer = 1;
constexpr UINT_PTR kExitGraceTimer = 2;
constexpr UINT kBalloonGuardMs = 12000;
constexpr UINT kExitGraceMs = 4000;

const flutter::EncodableValue* Find(const flutter::EncodableMap& map,
                                    const char* key) {
  auto it = map.find(flutter::EncodableValue(key));
  return it == map.end() ? nullptr : &it->second;
}

std::string StringArg(const flutter::EncodableMap& map, const char* key) {
  const auto* value = Find(map, key);
  if (value != nullptr && std::holds_alternative<std::string>(*value)) {
    return std::get<std::string>(*value);
  }
  return std::string();
}

bool IntValue(const flutter::EncodableValue* value, int* out) {
  if (value == nullptr) {
    return false;
  }
  if (std::holds_alternative<int32_t>(*value)) {
    *out = std::get<int32_t>(*value);
    return true;
  }
  if (std::holds_alternative<int64_t>(*value)) {
    const int64_t wide = std::get<int64_t>(*value);
    if (wide < INT32_MIN || wide > INT32_MAX) {
      return false;
    }
    *out = static_cast<int>(wide);
    return true;
  }
  return false;
}

struct DisplayEntry {
  RECT work;
  bool primary;
};

BOOL CALLBACK CollectMonitor(HMONITOR monitor, HDC, LPRECT, LPARAM data) {
  MONITORINFO info = {};
  info.cbSize = sizeof(info);
  if (::GetMonitorInfoW(monitor, &info)) {
    auto* list = reinterpret_cast<std::vector<DisplayEntry>*>(data);
    list->push_back({info.rcWork, (info.dwFlags & MONITORINFOF_PRIMARY) != 0});
  }
  return TRUE;
}

// GetWindowPlacement and SetWindowPlacement use "workspace" coordinates: screen
// coordinates relative to the work area of the primary display. Dart works in
// screen coordinates, so convert with this origin.
RECT PrimaryWorkArea() {
  const POINT origin = {0, 0};
  MONITORINFO info = {};
  info.cbSize = sizeof(info);
  HMONITOR primary = ::MonitorFromPoint(origin, MONITOR_DEFAULTTOPRIMARY);
  if (primary == nullptr || !::GetMonitorInfoW(primary, &info)) {
    return RECT{0, 0, 0, 0};
  }
  return info.rcWork;
}

}  // namespace

UINT DesktopIntegration::ActivateMessage() {
  static const UINT message = ::RegisterWindowMessageW(L"Nexora.Activate");
  return message;
}

DesktopIntegration::DesktopIntegration(HWND window,
                                       flutter::BinaryMessenger* messenger)
    : window_(window),
      taskbar_created_message_(::RegisterWindowMessageW(L"TaskbarCreated")) {
  channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      messenger, "nexora/desktop", &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        if (call.method_name() == "ready") {
          dart_ready_ = true;
          if (pending_click_) {
            pending_click_ = false;
            NotifyDart("notificationClicked", pending_click_task_, true);
          }
          result->Success();
        } else if (call.method_name() == "showNotification") {
          const auto* args =
              std::get_if<flutter::EncodableMap>(call.arguments());
          bool shown = false;
          if (args != nullptr) {
            shown = ShowNotification(StringArg(*args, "taskId"),
                                     StringArg(*args, "title"),
                                     StringArg(*args, "body"));
          }
          result->Success(flutter::EncodableValue(shown));
        } else if (call.method_name() == "quit") {
          result->Success();
          Quit();
        } else if (call.method_name() == "getDisplays") {
          result->Success(DisplaysValue());
        } else if (call.method_name() == "setWindowPlacement") {
          const auto* args =
              std::get_if<flutter::EncodableMap>(call.arguments());
          result->Success(flutter::EncodableValue(
              args != nullptr && ApplyPlacement(*args)));
        } else {
          result->NotImplemented();
        }
      });
  AddTrayIcon();
}

DesktopIntegration::~DesktopIntegration() {
  ::KillTimer(window_, kBalloonGuardTimer);
  ::KillTimer(window_, kExitGraceTimer);
  RemoveTrayIcon();
  if (channel_) {
    channel_->SetMethodCallHandler(nullptr);
  }
}

std::wstring DesktopIntegration::Widen(const std::string& utf8,
                                       size_t max_chars) {
  if (utf8.empty()) {
    return std::wstring();
  }
  int length = ::MultiByteToWideChar(CP_UTF8, 0, utf8.data(),
                                     static_cast<int>(utf8.size()), nullptr, 0);
  if (length <= 0) {
    return std::wstring();
  }
  std::wstring wide(static_cast<size_t>(length), L'\0');
  ::MultiByteToWideChar(CP_UTF8, 0, utf8.data(), static_cast<int>(utf8.size()),
                        &wide[0], length);
  if (wide.size() > max_chars) {
    wide.resize(max_chars);
  }
  return wide;
}

void DesktopIntegration::AddTrayIcon() {
  NOTIFYICONDATAW data = {};
  data.cbSize = sizeof(data);
  data.hWnd = window_;
  data.uID = kTrayIconId;
  data.uFlags = NIF_ICON | NIF_MESSAGE | NIF_TIP;
  data.uCallbackMessage = kTrayMessage;
  data.hIcon = ::LoadIconW(::GetModuleHandleW(nullptr),
                           MAKEINTRESOURCEW(IDI_APP_ICON));
  wcsncpy_s(data.szTip, L"Nexora", _TRUNCATE);
  // NIM_ADD fails when an icon with this id already exists: never two icons.
  tray_added_ = ::Shell_NotifyIconW(NIM_ADD, &data) == TRUE || tray_added_;
}

void DesktopIntegration::RemoveTrayIcon() {
  if (!tray_added_) {
    return;
  }
  NOTIFYICONDATAW data = {};
  data.cbSize = sizeof(data);
  data.hWnd = window_;
  data.uID = kTrayIconId;
  ::Shell_NotifyIconW(NIM_DELETE, &data);
  tray_added_ = false;
}

void DesktopIntegration::ShowMainWindow() {
  if (!::IsWindowVisible(window_)) {
    ::ShowWindow(window_, SW_SHOW);
  }
  if (::IsIconic(window_)) {
    ::ShowWindow(window_, SW_RESTORE);
  }
  ::SetForegroundWindow(window_);
  if (dart_ready_) {
    channel_->InvokeMethod("windowActivated", nullptr);
  }
}

void DesktopIntegration::ShowTrayMenu() {
  HMENU menu = ::CreatePopupMenu();
  if (menu == nullptr) {
    return;
  }
  ::AppendMenuW(menu, MF_STRING, kMenuOpen, L"Open Nexora");
  ::AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
  ::AppendMenuW(menu, MF_STRING, kMenuExit, L"Exit");
  POINT cursor;
  ::GetCursorPos(&cursor);
  // The window must be foreground, or the menu does not close on a click
  // elsewhere.
  ::SetForegroundWindow(window_);
  ::TrackPopupMenu(menu, TPM_RIGHTBUTTON | TPM_BOTTOMALIGN, cursor.x, cursor.y,
                   0, window_, nullptr);
  ::PostMessageW(window_, WM_NULL, 0, 0);
  ::DestroyMenu(menu);
}

bool DesktopIntegration::ShowNotification(const std::string& task_id,
                                          const std::string& title,
                                          const std::string& body) {
  if (!tray_added_) {
    return false;
  }
  Notification note;
  note.task_id = task_id;
  note.title = Widen(title, 63);
  note.body = Widen(body, 255);
  queue_.push_back(std::move(note));
  if (!balloon_active_) {
    ShowNextBalloon();
  }
  return true;
}

void DesktopIntegration::ShowNextBalloon() {
  if (queue_.empty()) {
    balloon_active_ = false;
    return;
  }
  Notification note = std::move(queue_.front());
  queue_.pop_front();
  NOTIFYICONDATAW data = {};
  data.cbSize = sizeof(data);
  data.hWnd = window_;
  data.uID = kTrayIconId;
  data.uFlags = NIF_INFO;
  data.dwInfoFlags = NIIF_INFO;
  wcsncpy_s(data.szInfoTitle, note.title.c_str(), _TRUNCATE);
  wcsncpy_s(data.szInfo, note.body.c_str(), _TRUNCATE);
  balloon_active_ = true;
  active_task_ = note.task_id;
  last_task_ = note.task_id;
  if (::Shell_NotifyIconW(NIM_MODIFY, &data) != TRUE) {
    balloon_active_ = false;
    ShowNextBalloon();
    return;
  }
  // Some shells never report the end of a balloon: the guard timer moves on.
  ::SetTimer(window_, kBalloonGuardTimer, kBalloonGuardMs, nullptr);
}

void DesktopIntegration::EndActiveBalloon() {
  ::KillTimer(window_, kBalloonGuardTimer);
  balloon_active_ = false;
  active_task_.clear();
  ShowNextBalloon();
}

void DesktopIntegration::NotifyDart(const char* method,
                                    const std::string& task_id,
                                    bool with_task) {
  if (with_task) {
    flutter::EncodableMap args;
    args[flutter::EncodableValue("taskId")] = flutter::EncodableValue(task_id);
    channel_->InvokeMethod(
        method, std::make_unique<flutter::EncodableValue>(std::move(args)));
  } else {
    channel_->InvokeMethod(method, nullptr);
  }
}

flutter::EncodableValue DesktopIntegration::DisplaysValue() const {
  std::vector<DisplayEntry> displays;
  ::EnumDisplayMonitors(nullptr, nullptr, CollectMonitor,
                        reinterpret_cast<LPARAM>(&displays));
  // The primary display first: Dart falls back to it.
  std::stable_sort(displays.begin(), displays.end(),
                   [](const DisplayEntry& a, const DisplayEntry& b) {
                     return a.primary && !b.primary;
                   });
  flutter::EncodableList list;
  for (const DisplayEntry& display : displays) {
    flutter::EncodableMap item;
    item[flutter::EncodableValue("left")] =
        flutter::EncodableValue(static_cast<int32_t>(display.work.left));
    item[flutter::EncodableValue("top")] =
        flutter::EncodableValue(static_cast<int32_t>(display.work.top));
    item[flutter::EncodableValue("right")] =
        flutter::EncodableValue(static_cast<int32_t>(display.work.right));
    item[flutter::EncodableValue("bottom")] =
        flutter::EncodableValue(static_cast<int32_t>(display.work.bottom));
    list.push_back(flutter::EncodableValue(std::move(item)));
  }
  return flutter::EncodableValue(std::move(list));
}

bool DesktopIntegration::ApplyPlacement(const flutter::EncodableMap& args) {
  int left = 0, top = 0, width = 0, height = 0;
  const auto* maximized = Find(args, "maximized");
  if (!IntValue(Find(args, "left"), &left) ||
      !IntValue(Find(args, "top"), &top) ||
      !IntValue(Find(args, "width"), &width) ||
      !IntValue(Find(args, "height"), &height) || maximized == nullptr ||
      !std::holds_alternative<bool>(*maximized) || width < 200 ||
      height < 150) {
    return false;
  }
  show_maximized_ = std::get<bool>(*maximized);
  if (!::IsWindowVisible(window_)) {
    // Not shown yet: set the restored bounds without showing the window. The
    // first-frame callback then shows it maximized or normal.
    return ::SetWindowPos(window_, nullptr, left, top, width, height,
                          SWP_NOZORDER | SWP_NOACTIVATE) == TRUE;
  }
  const RECT work = PrimaryWorkArea();
  WINDOWPLACEMENT placement = {};
  placement.length = sizeof(placement);
  placement.showCmd = show_maximized_ ? SW_SHOWMAXIMIZED : SW_SHOWNORMAL;
  placement.rcNormalPosition = {left - work.left, top - work.top,
                                left + width - work.left,
                                top + height - work.top};
  return ::SetWindowPlacement(window_, &placement) == TRUE;
}

bool DesktopIntegration::CurrentPlacement(flutter::EncodableMap* out) const {
  WINDOWPLACEMENT placement = {};
  placement.length = sizeof(placement);
  if (!::GetWindowPlacement(window_, &placement)) {
    return false;
  }
  const bool minimized = placement.showCmd == SW_SHOWMINIMIZED;
  const bool maximized =
      placement.showCmd == SW_SHOWMAXIMIZED ||
      (minimized && (placement.flags & WPF_RESTORETOMAXIMIZED) != 0);
  const RECT work = PrimaryWorkArea();
  const RECT normal = placement.rcNormalPosition;
  (*out)[flutter::EncodableValue("left")] =
      flutter::EncodableValue(static_cast<int32_t>(normal.left + work.left));
  (*out)[flutter::EncodableValue("top")] =
      flutter::EncodableValue(static_cast<int32_t>(normal.top + work.top));
  (*out)[flutter::EncodableValue("width")] = flutter::EncodableValue(
      static_cast<int32_t>(normal.right - normal.left));
  (*out)[flutter::EncodableValue("height")] = flutter::EncodableValue(
      static_cast<int32_t>(normal.bottom - normal.top));
  (*out)[flutter::EncodableValue("maximized")] =
      flutter::EncodableValue(maximized);
  return true;
}

void DesktopIntegration::NotifyPlacement() {
  // Only a visible, not minimized window has a placement worth remembering, and
  // only once Dart listens.
  if (!dart_ready_ || !::IsWindowVisible(window_) || ::IsIconic(window_)) {
    return;
  }
  flutter::EncodableMap placement;
  if (CurrentPlacement(&placement)) {
    channel_->InvokeMethod("windowPlacementChanged",
                           std::make_unique<flutter::EncodableValue>(
                               std::move(placement)));
  }
}

void DesktopIntegration::RequestExit() {
  if (!dart_ready_) {
    Quit();
    return;
  }
  // Dart saves and closes the runtime, then calls quit(). If it does not answer
  // in time the process ends anyway: an explicit Exit always terminates.
  ::SetTimer(window_, kExitGraceTimer, kExitGraceMs, nullptr);
  NotifyDart("exitRequested", std::string(), false);
}

void DesktopIntegration::Quit() {
  ::KillTimer(window_, kExitGraceTimer);
  RemoveTrayIcon();
  // Asynchronous: this may run inside the channel handler, which must not be
  // destroyed while it executes. WM_CLOSE ends in DestroyWindow, then the
  // message loop quits (SetQuitOnClose).
  ::PostMessageW(window_, WM_CLOSE, 0, 0);
}

bool DesktopIntegration::HandleMessage(HWND hwnd, UINT message, WPARAM wparam,
                                       LPARAM lparam, LRESULT* result) {
  if (message == ActivateMessage()) {
    ShowMainWindow();
    *result = 0;
    return true;
  }
  if (message == taskbar_created_message_) {
    // Explorer restarted: the tray icon is gone, add it again.
    tray_added_ = false;
    AddTrayIcon();
    *result = 0;
    return true;
  }
  switch (message) {
    case kTrayMessage: {
      switch (LOWORD(lparam)) {
        case WM_LBUTTONUP:
        case WM_LBUTTONDBLCLK:
          ShowMainWindow();
          break;
        case WM_RBUTTONUP:
        case WM_CONTEXTMENU:
          ShowTrayMenu();
          break;
        case NIN_BALLOONUSERCLICK: {
          std::string task = balloon_active_ ? active_task_ : last_task_;
          ShowMainWindow();
          if (dart_ready_) {
            NotifyDart("notificationClicked", task, true);
          } else {
            pending_click_ = true;
            pending_click_task_ = task;
          }
          EndActiveBalloon();
          break;
        }
        case NIN_BALLOONTIMEOUT:
        case NIN_BALLOONHIDE:
          EndActiveBalloon();
          break;
        default:
          break;
      }
      *result = 0;
      return true;
    }
    case WM_COMMAND:
      if (LOWORD(wparam) == kMenuOpen) {
        ShowMainWindow();
        *result = 0;
        return true;
      }
      if (LOWORD(wparam) == kMenuExit) {
        RequestExit();
        *result = 0;
        return true;
      }
      return false;
    case WM_TIMER:
      if (wparam == kBalloonGuardTimer) {
        EndActiveBalloon();
        *result = 0;
        return true;
      }
      if (wparam == kExitGraceTimer) {
        Quit();
        *result = 0;
        return true;
      }
      return false;
    case WM_SIZE:
      if (wparam == SIZE_MINIMIZED) {
        // Minimize goes to the tray: hide after this message has finished.
        ::PostMessageW(hwnd, kHideMessage, 0, 0);
      } else if (!in_size_move_ &&
                 (wparam == SIZE_MAXIMIZED || wparam == SIZE_RESTORED)) {
        // Maximize, restore or a layout change outside a drag.
        NotifyPlacement();
      }
      return false;
    case WM_ENTERSIZEMOVE:
      in_size_move_ = true;
      return false;
    case WM_EXITSIZEMOVE:
      // The user finished dragging or resizing.
      in_size_move_ = false;
      NotifyPlacement();
      return false;
    case kHideMessage:
      if (::IsIconic(hwnd)) {
        ::ShowWindow(hwnd, SW_HIDE);
      }
      *result = 0;
      return true;
    default:
      return false;
  }
}
