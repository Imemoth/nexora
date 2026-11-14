#ifndef RUNNER_DESKTOP_INTEGRATION_H_
#define RUNNER_DESKTOP_INTEGRATION_H_

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <windows.h>
#include <shellapi.h>

#include <deque>
#include <memory>
#include <string>

// Windows shell integration for Nexora: one tray icon, native notifications
// (shell balloons, shown as toasts on Windows 10/11), minimize-to-tray and a
// bridge to Dart over the method channel "nexora/desktop".
//
// Channel protocol (Dart -> native):
//   ready()                                   Dart can now receive events.
//   showNotification({taskId,title,body})     -> bool (false: not shown).
//   quit()                                    Destroy the window and end.
// Native -> Dart:
//   notificationClicked({taskId})   a Nexora notification was clicked.
//   exitRequested()                 tray menu Exit; Dart saves, then calls quit().
//   windowActivated()               the window was restored from the tray.
class DesktopIntegration {
 public:
  DesktopIntegration(HWND window, flutter::BinaryMessenger* messenger);
  ~DesktopIntegration();

  DesktopIntegration(const DesktopIntegration&) = delete;
  DesktopIntegration& operator=(const DesktopIntegration&) = delete;

  // Gives the integration a look at a window message. Returns true when the
  // message was fully handled (the result is in |result|).
  bool HandleMessage(HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam,
                     LRESULT* result);

  // Registered message other Nexora processes post to ask this one to show
  // its window (single-instance activation).
  static UINT ActivateMessage();

  void ShowMainWindow();

 private:
  struct Notification {
    std::string task_id;
    std::wstring title;
    std::wstring body;
  };

  void AddTrayIcon();
  void RemoveTrayIcon();
  void ShowTrayMenu();
  bool ShowNotification(const std::string& task_id, const std::string& title,
                        const std::string& body);
  void ShowNextBalloon();
  void EndActiveBalloon();
  void RequestExit();
  void Quit();
  void NotifyDart(const char* method, const std::string& task_id,
                  bool with_task);

  static std::wstring Widen(const std::string& utf8, size_t max_chars);

  HWND window_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  bool tray_added_ = false;
  bool dart_ready_ = false;
  bool pending_click_ = false;
  std::string pending_click_task_;
  std::deque<Notification> queue_;
  bool balloon_active_ = false;
  std::string active_task_;
  std::string last_task_;
  UINT taskbar_created_message_;
};

#endif  // RUNNER_DESKTOP_INTEGRATION_H_
