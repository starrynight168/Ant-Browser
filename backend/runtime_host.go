package backend

import (
	"context"
	"fmt"
)

type DialogFilter struct {
	DisplayName string
	Pattern     string
}

type OpenDialogOptions struct {
	Title   string
	Filters []DialogFilter
}

type SaveDialogOptions struct {
	Title           string
	DefaultFilename string
	Filters         []DialogFilter
}

type MessageDialogOptions struct {
	Type    string
	Title   string
	Message string
}

func (a *App) runtimeHostSnapshot() (RuntimeHost, context.Context) {
	if a == nil {
		return nil, nil
	}
	a.runtimeMu.RLock()
	defer a.runtimeMu.RUnlock()
	return a.runtimeHost, a.ctx
}

func (a *App) openFileDialog(options OpenDialogOptions) (string, error) {
	host, ctx := a.runtimeHostSnapshot()
	if host == nil || ctx == nil {
		return "", fmt.Errorf("桌面界面未连接")
	}
	return host.OpenFileDialog(ctx, options)
}

func (a *App) openDirectoryDialog(options OpenDialogOptions) (string, error) {
	host, ctx := a.runtimeHostSnapshot()
	if host == nil || ctx == nil {
		return "", fmt.Errorf("桌面界面未连接")
	}
	return host.OpenDirectoryDialog(ctx, options)
}

func (a *App) saveFileDialog(options SaveDialogOptions) (string, error) {
	host, ctx := a.runtimeHostSnapshot()
	if host == nil || ctx == nil {
		return "", fmt.Errorf("桌面界面未连接")
	}
	return host.SaveFileDialog(ctx, options)
}

func (a *App) messageDialog(options MessageDialogOptions) (string, error) {
	host, ctx := a.runtimeHostSnapshot()
	if host == nil || ctx == nil {
		return "", fmt.Errorf("桌面界面未连接")
	}
	return host.MessageDialog(ctx, options)
}
