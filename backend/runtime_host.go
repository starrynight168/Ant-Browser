package backend

import (
	"context"
	"fmt"
)

type DialogFilter struct {
	DisplayName string `json:"displayName"`
	Pattern     string `json:"pattern"`
}

type OpenDialogOptions struct {
	Title   string         `json:"title"`
	Filters []DialogFilter `json:"filters"`
}

type SaveDialogOptions struct {
	Title           string         `json:"title"`
	DefaultFilename string         `json:"defaultFilename"`
	Filters         []DialogFilter `json:"filters"`
}

type MessageDialogOptions struct {
	Type    string `json:"type"`
	Title   string `json:"title"`
	Message string `json:"message"`
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
