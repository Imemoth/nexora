#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include <cwchar>

#include "desktop_integration.h"
#include "flutter_window.h"
#include "utils.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // One Nexora per user session: a second launch asks the running one to show
  // its window and exits, so there is never a second tray icon. Development
  // self-tests (which run the executable headless) skip the check.
  HANDLE instance_mutex = nullptr;
  const bool self_test = ::GetEnvironmentVariableW(L"NEXORA_AUTH_SELFTEST",
                                                   nullptr, 0) > 0 ||
                         wcsstr(command_line, L"--auth-selftest") != nullptr;
  if (!self_test) {
    instance_mutex = ::CreateMutexW(nullptr, TRUE, L"Local\\Nexora.SingleInstance");
    if (instance_mutex != nullptr && ::GetLastError() == ERROR_ALREADY_EXISTS) {
      // This process was just started by the user, so Windows lets it hand the
      // right to take the foreground to the running instance
      // (AllowSetForegroundWindow). Without the grant, SetForegroundWindow in
      // the running instance only flashes its taskbar button when another
      // application is in front. The grant is a request: Windows may still
      // refuse (for example when the launch did not come from user input), and
      // then the window is restored and the taskbar button flashes, as before.
      HWND running = ::FindWindowW(L"FLUTTER_RUNNER_WIN32_WINDOW", L"nexora");
      if (running != nullptr) {
        DWORD running_pid = 0;
        ::GetWindowThreadProcessId(running, &running_pid);
        if (running_pid != 0) {
          ::AllowSetForegroundWindow(running_pid);
        }
      }
      ::PostMessageW(HWND_BROADCAST, DesktopIntegration::ActivateMessage(), 0,
                     0);
      ::CloseHandle(instance_mutex);
      return EXIT_SUCCESS;
    }
  }

  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"nexora", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  if (instance_mutex != nullptr) {
    ::CloseHandle(instance_mutex);
  }
  return EXIT_SUCCESS;
}
