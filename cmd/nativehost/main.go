package main

import (
	"ant-chrome/backend"
	"ant-chrome/internal/lifecycle"
	"ant-chrome/internal/singleinstance"
	"ant-chrome/internal/windowsizing"
	"context"
	"errors"
	"log"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"sync/atomic"
	"time"
)

var appVersion = "1.9.4"

func main() {
	appRoot := resolveAppRoot()
	lifecycle.Log(appRoot, "process.start", map[string]interface{}{"native": true})
	defer lifecycle.Log(appRoot, "process.defer_exit", map[string]interface{}{"native": true})
	if err := os.Chdir(appRoot); err != nil {
		log.Printf("切换应用目录失败: %v", err)
		lifecycle.Log(appRoot, "app_root.chdir.error", map[string]interface{}{"error": err.Error()})
		return
	}
	if err := backend.EnsureRuntimeLayout(appRoot); err != nil {
		log.Printf("准备用户数据目录失败: %v", err)
		lifecycle.Log(appRoot, "runtime_layout.error", map[string]interface{}{"error": err.Error()})
		return
	}
	guard, primary, err := singleinstance.Acquire(appRoot)
	if err != nil {
		log.Printf("单实例检查失败: %v", err)
		lifecycle.Log(appRoot, "single_instance.error", map[string]interface{}{"error": err.Error()})
		return
	}
	if !primary {
		lifecycle.Log(appRoot, "process.exit.non_primary", nil)
		return
	}
	lifecycle.Log(appRoot, "single_instance.checked", map[string]interface{}{"primary": true})
	defer guard.Close()
	var uiPID atomic.Int64
	uiStarted := make(chan struct{})
	go func() {
		for activation := range guard.Activations() {
			select {
			case <-uiStarted:
			case <-time.After(12 * time.Second):
			}
			if pid := uiPID.Load(); pid > 0 {
				deadline := time.Now().Add(12 * time.Second)
				for !singleinstance.HasExistingWindow(int(pid)) && time.Now().Before(deadline) {
					time.Sleep(80 * time.Millisecond)
				}
				if singleinstance.HasExistingWindow(int(pid)) {
					singleinstance.ActivateExistingWindow(int(pid))
				}
			}
			activation.Complete()
		}
	}()

	app := backend.NewApp(appRoot, appVersion)
	rpc, err := backend.NewNativeRPCServer(app)
	if err != nil {
		log.Printf("启动本地界面接口失败: %v", err)
		lifecycle.Log(appRoot, "native_rpc.start.error", map[string]interface{}{"error": err.Error()})
		return
	}
	ctx := context.Background()
	if err := backend.Start(app, ctx); err != nil {
		log.Printf("应用启动失败: %v", err)
		lifecycle.Log(appRoot, "backend.start.error", map[string]interface{}{"error": err.Error()})
		backend.Stop(app, ctx)
		_ = rpc.Close(context.Background())
		return
	}
	lifecycle.Log(appRoot, "backend.start.complete", nil)
	windowConfig := app.GetAppConfig()
	windowBounds := windowsizing.ResolveStartupWindowBounds(windowsizing.StartupWindowBounds{
		Width:     intConfigValue(windowConfig, "windowWidth"),
		Height:    intConfigValue(windowConfig, "windowHeight"),
		MinWidth:  intConfigValue(windowConfig, "windowMinWidth"),
		MinHeight: intConfigValue(windowConfig, "windowMinHeight"),
	})

	uiPath := resolveUIPath()
	if _, err := os.Stat(uiPath); err != nil {
		log.Printf("找不到 Flutter 界面程序 %q: %v", uiPath, err)
		lifecycle.Log(appRoot, "flutter_ui.missing", map[string]interface{}{"path": uiPath, "error": err.Error()})
		backend.Stop(app, ctx)
		_ = rpc.Close(context.Background())
		return
	}
	ui := exec.Command(uiPath)
	ui.Dir = filepath.Dir(uiPath)
	ui.Env = append(os.Environ(),
		"ANT_BROWSER_NATIVE_RPC_URL="+rpc.Address(),
		"ANT_BROWSER_NATIVE_RPC_TOKEN="+rpc.Token(),
		"ANT_BROWSER_WINDOW_TITLE="+stringConfigValue(windowConfig, "name"),
		"ANT_BROWSER_WINDOW_WIDTH="+strconv.Itoa(windowBounds.Width),
		"ANT_BROWSER_WINDOW_HEIGHT="+strconv.Itoa(windowBounds.Height),
		"ANT_BROWSER_WINDOW_MIN_WIDTH="+strconv.Itoa(windowBounds.MinWidth),
		"ANT_BROWSER_WINDOW_MIN_HEIGHT="+strconv.Itoa(windowBounds.MinHeight),
	)
	if err := ui.Start(); err != nil {
		log.Printf("启动 Flutter 界面失败: %v", err)
		lifecycle.Log(appRoot, "flutter_ui.start.error", map[string]interface{}{"path": uiPath, "error": err.Error()})
		backend.Stop(app, ctx)
		_ = rpc.Close(context.Background())
		return
	}
	uiPID.Store(int64(ui.Process.Pid))
	close(uiStarted)
	lifecycle.Log(appRoot, "flutter_ui.start.complete", map[string]interface{}{"pid": ui.Process.Pid, "path": uiPath})
	go lifecycle.RunTraySafely(appRoot, backend.TrayCallbacks{
		OnShow: func() {
			lifecycle.Log(appRoot, "tray.show", nil)
			if pid := uiPID.Load(); pid > 0 {
				singleinstance.ActivateExistingWindow(int(pid))
			}
		},
		OnQuitAppOnly: func() {
			lifecycle.Log(appRoot, "tray.quit_app_only", nil)
			app.QuitAppOnly()
		},
		OnQuit: func() {
			lifecycle.Log(appRoot, "tray.quit", nil)
			if pid := uiPID.Load(); pid > 0 {
				singleinstance.HideExistingWindow(int(pid))
			}
			app.ForceQuit()
		},
		OnExit: func() {
			lifecycle.Log(appRoot, "tray.exit", nil)
		},
	})
	uiExited := make(chan error, 1)
	go func() { uiExited <- ui.Wait() }()

	select {
	case err := <-uiExited:
		if err != nil && !errors.Is(err, os.ErrProcessDone) {
			log.Printf("Flutter 界面已退出: %v", err)
			lifecycle.Log(appRoot, "flutter_ui.exit.error", map[string]interface{}{"error": err.Error()})
		} else {
			lifecycle.Log(appRoot, "flutter_ui.exit", nil)
		}
	case <-rpc.QuitRequested():
		lifecycle.Log(appRoot, "application.quit.requested", nil)
		_ = ui.Process.Kill()
		<-uiExited
	}

	backend.QuitTray()
	lifecycle.Log(appRoot, "backend.stop.begin", nil)
	backend.Stop(app, ctx)
	lifecycle.Log(appRoot, "backend.stop.complete", nil)
	shutdownCtx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()
	if err := rpc.Close(shutdownCtx); err != nil {
		log.Printf("关闭本地界面接口失败: %v", err)
		lifecycle.Log(appRoot, "native_rpc.stop.error", map[string]interface{}{"error": err.Error()})
	}
}

func intConfigValue(config map[string]interface{}, key string) int {
	value, _ := config[key].(int)
	return value
}

func stringConfigValue(config map[string]interface{}, key string) string {
	value, _ := config[key].(string)
	return value
}

func resolveAppRoot() string {
	if configuredRoot := strings.TrimSpace(os.Getenv("ANT_BROWSER_APP_ROOT")); configuredRoot != "" {
		if absoluteRoot, err := filepath.Abs(configuredRoot); err == nil {
			return absoluteRoot
		}
		return configuredRoot
	}
	executable, err := os.Executable()
	if err == nil {
		directory := filepath.Dir(executable)
		cleanDirectory := filepath.ToSlash(strings.ToLower(directory))
		if strings.HasSuffix(cleanDirectory, "/build/bin") ||
			strings.HasSuffix(cleanDirectory, "/build/native") {
			if workingDirectory, err := os.Getwd(); err == nil {
				return workingDirectory
			}
		}
		return directory
	}
	if workingDirectory, err := os.Getwd(); err == nil {
		return workingDirectory
	}
	return "."
}

func resolveUIPath() string {
	if configured := strings.TrimSpace(os.Getenv("ANT_BROWSER_FLUTTER_UI")); configured != "" {
		return configured
	}
	executable, err := os.Executable()
	if err != nil {
		return "ant-browser-ui.exe"
	}
	return filepath.Join(filepath.Dir(executable), "ant-browser-ui.exe")
}
