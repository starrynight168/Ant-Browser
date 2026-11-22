package main

import (
	"ant-chrome/backend"
	"ant-chrome/internal/lifecycle"
	"ant-chrome/internal/singleinstance"
	"context"
	"errors"
	"log"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"sync/atomic"
	"time"
)

var appVersion = "1.9.4"

func main() {
	appRoot := resolveAppRoot()
	if err := backend.EnsureRuntimeLayout(appRoot); err != nil {
		log.Printf("准备用户数据目录失败: %v", err)
		return
	}
	guard, primary, err := singleinstance.Acquire(appRoot)
	if err != nil {
		log.Printf("单实例检查失败: %v", err)
		return
	}
	if !primary {
		return
	}
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
				singleinstance.ActivateExistingWindow(int(pid))
			}
			activation.Complete()
		}
	}()

	app := backend.NewApp(appRoot, appVersion)
	rpc, err := backend.NewNativeRPCServer(app)
	if err != nil {
		log.Printf("启动本地界面接口失败: %v", err)
		return
	}
	ctx := context.Background()
	if err := backend.Start(app, ctx); err != nil {
		log.Printf("应用启动失败: %v", err)
		_ = rpc.Close(context.Background())
		return
	}

	uiPath := resolveUIPath()
	if _, err := os.Stat(uiPath); err != nil {
		log.Printf("找不到 Flutter 界面程序 %q: %v", uiPath, err)
		backend.Stop(app, ctx)
		_ = rpc.Close(context.Background())
		return
	}
	ui := exec.Command(uiPath)
	ui.Env = append(os.Environ(),
		"ANT_BROWSER_NATIVE_RPC_URL="+rpc.Address(),
		"ANT_BROWSER_NATIVE_RPC_TOKEN="+rpc.Token(),
	)
	if err := ui.Start(); err != nil {
		log.Printf("启动 Flutter 界面失败: %v", err)
		backend.Stop(app, ctx)
		_ = rpc.Close(context.Background())
		return
	}
	uiPID.Store(int64(ui.Process.Pid))
	close(uiStarted)
	go lifecycle.RunTraySafely(appRoot, backend.TrayCallbacks{
		OnShow: func() {
			if pid := uiPID.Load(); pid > 0 {
				singleinstance.ActivateExistingWindow(int(pid))
			}
		},
		OnQuitAppOnly: app.QuitAppOnly,
		OnQuit:        app.ForceQuit,
	})
	uiExited := make(chan error, 1)
	go func() { uiExited <- ui.Wait() }()

	select {
	case err := <-uiExited:
		if err != nil && !errors.Is(err, os.ErrProcessDone) {
			log.Printf("Flutter 界面已退出: %v", err)
		}
	case <-rpc.QuitRequested():
		_ = ui.Process.Kill()
		<-uiExited
	}

	backend.Stop(app, ctx)
	shutdownCtx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()
	if err := rpc.Close(shutdownCtx); err != nil {
		log.Printf("关闭本地界面接口失败: %v", err)
	}
}

func resolveAppRoot() string {
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
