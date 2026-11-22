#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include <cwchar>
#include <limits>
#include <string>

#include "flutter_window.h"
#include "utils.h"

namespace {

std::wstring ReadEnvironmentString(const wchar_t* name,
                                   const std::wstring& fallback) {
  const DWORD required = GetEnvironmentVariableW(name, nullptr, 0);
  if (required == 0) return fallback;
  std::wstring value(required, L'\0');
  const DWORD written = GetEnvironmentVariableW(name, value.data(), required);
  if (written == 0 || written >= required) return fallback;
  value.resize(written);
  return value;
}

unsigned int ReadEnvironmentSize(const wchar_t* name,
                                unsigned int fallback) {
  wchar_t value[32]{};
  const DWORD written = GetEnvironmentVariableW(name, value, 32);
  if (written == 0 || written >= 32) return fallback;
  wchar_t* end = nullptr;
  const unsigned long parsed = std::wcstoul(value, &end, 10);
  if (end == value || *end != L'\0' || parsed == 0 ||
      parsed > std::numeric_limits<unsigned int>::max()) {
    return fallback;
  }
  return static_cast<unsigned int>(parsed);
}

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
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
  Win32Window::Size size(
      ReadEnvironmentSize(L"ANT_BROWSER_WINDOW_WIDTH", 1280),
      ReadEnvironmentSize(L"ANT_BROWSER_WINDOW_HEIGHT", 800));
  window.SetMinimumSize(Win32Window::Size(
      ReadEnvironmentSize(L"ANT_BROWSER_WINDOW_MIN_WIDTH", 0),
      ReadEnvironmentSize(L"ANT_BROWSER_WINDOW_MIN_HEIGHT", 0)));
  const std::wstring title =
      ReadEnvironmentString(L"ANT_BROWSER_WINDOW_TITLE", L"Ant Browser");
  if (!window.Create(title, origin, size)) {
    return EXIT_FAILURE;
  }
  window.CenterToMonitor();
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
