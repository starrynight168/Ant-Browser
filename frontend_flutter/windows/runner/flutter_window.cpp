#include "flutter_window.h"

#include <shobjidl.h>
#include <shellapi.h>
#include <wrl/client.h>

#include <optional>
#include <string>
#include <utility>
#include <variant>
#include <vector>

#include "flutter/generated_plugin_registrant.h"

namespace {

using flutter::EncodableList;
using flutter::EncodableMap;
using flutter::EncodableValue;

const EncodableValue* FindValue(const EncodableValue* value,
                                const std::string& key) {
  if (value == nullptr || !std::holds_alternative<EncodableMap>(*value)) {
    return nullptr;
  }
  const auto& map = std::get<EncodableMap>(*value);
  const auto iterator = map.find(EncodableValue(key));
  return iterator == map.end() ? nullptr : &iterator->second;
}

std::string StringValue(const EncodableValue* value) {
  if (value == nullptr || !std::holds_alternative<std::string>(*value)) {
    return {};
  }
  return std::get<std::string>(*value);
}

std::wstring ToWide(const std::string& value) {
  if (value.empty()) return {};
  const int size = MultiByteToWideChar(CP_UTF8, 0, value.data(),
                                       static_cast<int>(value.size()), nullptr, 0);
  std::wstring result(size, L'\0');
  MultiByteToWideChar(CP_UTF8, 0, value.data(), static_cast<int>(value.size()),
                      result.data(), size);
  return result;
}

std::string ToUtf8(const std::wstring& value) {
  if (value.empty()) return {};
  const int size = WideCharToMultiByte(CP_UTF8, 0, value.data(),
                                       static_cast<int>(value.size()), nullptr, 0,
                                       nullptr, nullptr);
  std::string result(size, '\0');
  WideCharToMultiByte(CP_UTF8, 0, value.data(), static_cast<int>(value.size()),
                      result.data(), size, nullptr, nullptr);
  return result;
}

std::string SystemTimezone() {
  const auto icu = LoadLibraryExW(L"icu.dll", nullptr, LOAD_LIBRARY_SEARCH_SYSTEM32);
  if (!icu) return {};
  using GetHostTimezone = int32_t (*)(wchar_t*, int32_t, int32_t*);
  const auto get_host_timezone = reinterpret_cast<GetHostTimezone>(
      GetProcAddress(icu, "ucal_getHostTimeZone"));
  wchar_t zone[128] = {};
  int32_t status = 0;
  const auto length = get_host_timezone ? get_host_timezone(zone, 128, &status) : 0;
  FreeLibrary(icu);
  if (status > 0 || length <= 0 || length >= 128) return {};
  const std::wstring id(zone, length);
  return id == L"Etc/Unknown" ? std::string{} : ToUtf8(id);
}

std::vector<COMDLG_FILTERSPEC> BuildFilters(const EncodableValue* value,
                                           std::vector<std::wstring>* names,
                                           std::vector<std::wstring>* patterns) {
  std::vector<COMDLG_FILTERSPEC> filters;
  if (value == nullptr || !std::holds_alternative<EncodableList>(*value)) {
    return filters;
  }
  for (const auto& item : std::get<EncodableList>(*value)) {
    const auto* name = FindValue(&item, "displayName");
    const auto* pattern = FindValue(&item, "pattern");
    const auto displayName = ToWide(StringValue(name));
    const auto filePattern = ToWide(StringValue(pattern));
    if (displayName.empty() || filePattern.empty()) continue;
    names->push_back(displayName);
    patterns->push_back(filePattern);
  }
  filters.reserve(names->size());
  for (size_t index = 0; index < names->size(); ++index) {
    filters.push_back({(*names)[index].c_str(), (*patterns)[index].c_str()});
  }
  return filters;
}

HRESULT PickPath(HWND owner, bool save, bool directory, const std::wstring& title,
                 const std::wstring& fileName,
                 const std::vector<COMDLG_FILTERSPEC>& filters,
                 std::wstring* path) {
  Microsoft::WRL::ComPtr<IFileDialog> dialog;
  const CLSID classId = save ? CLSID_FileSaveDialog : CLSID_FileOpenDialog;
  HRESULT status = CoCreateInstance(classId, nullptr, CLSCTX_INPROC_SERVER,
                                    IID_PPV_ARGS(&dialog));
  if (FAILED(status)) return status;

  if (!title.empty()) dialog->SetTitle(title.c_str());
  if (!fileName.empty()) dialog->SetFileName(fileName.c_str());
  if (!filters.empty()) {
    status = dialog->SetFileTypes(static_cast<UINT>(filters.size()), filters.data());
    if (FAILED(status)) return status;
    dialog->SetFileTypeIndex(1);
  }

  DWORD options = 0;
  status = dialog->GetOptions(&options);
  if (FAILED(status)) return status;
  options |= FOS_FORCEFILESYSTEM | FOS_PATHMUSTEXIST;
  if (directory) {
    options |= FOS_PICKFOLDERS;
  } else if (!save) {
    options |= FOS_FILEMUSTEXIST;
  }
  status = dialog->SetOptions(options);
  if (FAILED(status)) return status;

  status = dialog->Show(owner);
  if (status == HRESULT_FROM_WIN32(ERROR_CANCELLED)) return S_FALSE;
  if (FAILED(status)) return status;

  Microsoft::WRL::ComPtr<IShellItem> item;
  status = dialog->GetResult(&item);
  if (FAILED(status)) return status;
  PWSTR selectedPath = nullptr;
  status = item->GetDisplayName(SIGDN_FILESYSPATH, &selectedPath);
  if (FAILED(status)) return status;
  *path = selectedPath;
  CoTaskMemFree(selectedPath);
  return S_OK;
}

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());
  host_channel_ = std::make_unique<flutter::MethodChannel<EncodableValue>>(
      flutter_controller_->engine()->messenger(), "ant_browser/platform",
      &flutter::StandardMethodCodec::GetInstance());
  host_channel_->SetMethodCallHandler(
      [this](const auto& call, auto result) {
        HandleHostMethod(call, std::move(result));
      });

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  if (flutter_controller_) {
    host_channel_.reset();
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  if (message == WM_CLOSE) {
    if (close_allowed_) {
      close_allowed_ = false;
    } else if (host_channel_) {
      host_channel_->InvokeMethod("windowCloseRequested",
                                  std::make_unique<EncodableValue>());
      return 0;
    }
  }

  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}

void FlutterWindow::HandleHostMethod(
    const flutter::MethodCall<EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
  const auto& method = call.method_name();

  if (method == "systemTimezone") {
    result->Success(EncodableValue(SystemTimezone()));
    return;
  }
  const auto* arguments = call.arguments();
  if (method == "window.hide") {
    ShowWindow(GetHandle(), SW_HIDE);
    result->Success();
    return;
  }
  if (method == "window.minimize") {
    ShowWindow(GetHandle(), SW_MINIMIZE);
    result->Success();
    return;
  }
  if (method == "window.close") {
    close_allowed_ = true;
    PostMessage(GetHandle(), WM_CLOSE, 0, 0);
    result->Success();
    return;
  }
  if (method == "openExternal") {
    const auto url = ToWide(StringValue(arguments));
    if (!url.empty()) {
      ShellExecuteW(GetHandle(), L"open", url.c_str(), nullptr, nullptr,
                    SW_SHOWNORMAL);
    }
    result->Success();
    return;
  }
  if (method == "dialog.openFile" || method == "dialog.openDirectory" ||
      method == "dialog.saveFile") {
    const auto title = ToWide(StringValue(FindValue(arguments, "title")));
    const auto fileName = ToWide(StringValue(FindValue(arguments, "defaultFilename")));
    std::vector<std::wstring> names;
    std::vector<std::wstring> patterns;
    const auto filters = BuildFilters(FindValue(arguments, "filters"), &names, &patterns);
    std::wstring path;
    const bool save = method == "dialog.saveFile";
    const bool directory = method == "dialog.openDirectory";
    const HRESULT status = PickPath(GetHandle(), save, directory, title, fileName,
                                    filters, &path);
    if (status == S_FALSE) {
      result->Success(EncodableValue());
    } else if (FAILED(status)) {
      result->Error("file_dialog_failed", "Windows 文件选择窗口打开失败");
    } else {
      result->Success(EncodableValue(ToUtf8(path)));
    }
    return;
  }
  if (method == "dialog.message") {
    const auto type = StringValue(FindValue(arguments, "type"));
    const auto title = ToWide(StringValue(FindValue(arguments, "title")));
    const auto message = ToWide(StringValue(FindValue(arguments, "message")));
    UINT flags = MB_YESNO | MB_ICONQUESTION;
    if (type == "info") {
      flags = MB_OK | MB_ICONINFORMATION;
    } else if (type == "warning") {
      flags = MB_OK | MB_ICONWARNING;
    } else if (type == "error") {
      flags = MB_OK | MB_ICONERROR;
    }
    const int selection =
        MessageBoxW(GetHandle(), message.c_str(), title.c_str(), flags);
    if (selection == IDYES) {
      result->Success(EncodableValue("yes"));
    } else if (selection == IDOK) {
      result->Success(EncodableValue("ok"));
    } else {
      result->Success(EncodableValue("no"));
    }
    return;
  }
  result->NotImplemented();
}
