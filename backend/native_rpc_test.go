package backend

import (
	"bufio"
	"context"
	"encoding/json"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func openTestSSEStream(t *testing.T, server *NativeRPCServer) (*http.Response, *bufio.Reader) {
	t.Helper()
	req, err := http.NewRequest(http.MethodGet, server.Address()+"/api/v1/events", nil)
	if err != nil {
		t.Fatalf("create SSE request: %v", err)
	}
	req.Header.Set("Authorization", "Bearer "+server.Token())

	client := &http.Client{}
	resp, err := client.Do(req)
	if err != nil {
		t.Fatalf("connect SSE stream: %v", err)
	}
	if resp.StatusCode != http.StatusOK {
		_ = resp.Body.Close()
		t.Fatalf("unexpected SSE status: %d", resp.StatusCode)
	}
	return resp, bufio.NewReader(resp.Body)
}

func readNextSSEEvent(t *testing.T, reader *bufio.Reader, timeout time.Duration) nativeRuntimeEvent {
	t.Helper()
	type result struct {
		event nativeRuntimeEvent
		err   error
	}
	ch := make(chan result, 1)
	go func() {
		for {
			line, err := reader.ReadString('\n')
			if err != nil {
				ch <- result{err: err}
				return
			}
			line = strings.TrimSpace(line)
			if !strings.HasPrefix(line, "data:") {
				continue
			}
			raw := strings.TrimSpace(strings.TrimPrefix(line, "data:"))
			var event nativeRuntimeEvent
			if err := json.Unmarshal([]byte(raw), &event); err != nil {
				ch <- result{err: err}
				return
			}
			ch <- result{event: event}
			return
		}
	}()

	select {
	case res := <-ch:
		if res.err != nil {
			t.Fatalf("read SSE event: %v", res.err)
		}
		return res.event
	case <-time.After(timeout):
		t.Fatal("timed out waiting for SSE event")
		return nativeRuntimeEvent{}
	}
}

func TestNativeRPCServerStickyStartupEventReplay(t *testing.T) {
	app := NewApp(t.TempDir(), "test")
	server, err := NewNativeRPCServer(app)
	if err != nil {
		t.Fatalf("NewNativeRPCServer failed: %v", err)
	}
	defer func() {
		ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
		defer cancel()
		_ = server.Close(ctx)
	}()

	// Emit sticky startup events and one non-sticky event before any SSE client connects.
	server.EmitRuntimeEvent("app:non-sticky", "ignored")
	server.EmitRuntimeEvent("app:db-recovered", map[string]any{"recovered": true, "reason": "old"})
	server.EmitRuntimeEvent("app:db-recovered", map[string]any{"recovered": true, "reason": "latest"})
	server.EmitRuntimeEvent("app:update:pending", map[string]any{"version": "2.0.0"})
	server.EmitRuntimeEvent("app:ready")

	resp, reader := openTestSSEStream(t, server)
	defer func() { _ = resp.Body.Close() }()

	got := make([]nativeRuntimeEvent, 0, 3)
	for i := 0; i < 3; i++ {
		got = append(got, readNextSSEEvent(t, reader, 2*time.Second))
	}

	if got[0].Name != "app:db-recovered" {
		t.Fatalf("expected first replayed event app:db-recovered, got %q", got[0].Name)
	}
	payload0, ok := got[0].Args[0].(map[string]interface{})
	if !ok || payload0["reason"] != "latest" {
		t.Fatalf("expected latest app:db-recovered payload, got %#v", got[0].Args)
	}

	if got[1].Name != "app:update:pending" {
		t.Fatalf("expected second replayed event app:update:pending, got %q", got[1].Name)
	}
	payload1, ok := got[1].Args[0].(map[string]interface{})
	if !ok || payload1["version"] != "2.0.0" {
		t.Fatalf("expected app:update:pending payload, got %#v", got[1].Args)
	}

	if got[2].Name != "app:ready" {
		t.Fatalf("expected third replayed event app:ready, got %q", got[2].Name)
	}
}

func TestNativeRPCServerRequestDialogFailsFastWithoutSSEClient(t *testing.T) {
	app := NewApp(t.TempDir(), "test")
	server, err := NewNativeRPCServer(app)
	if err != nil {
		t.Fatalf("NewNativeRPCServer failed: %v", err)
	}
	defer func() {
		ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
		defer cancel()
		_ = server.Close(ctx)
	}()

	done := make(chan error, 1)
	go func() {
		_, err := server.MessageDialog(context.Background(), MessageDialogOptions{
			Type:    "info",
			Title:   "Info",
			Message: "No client",
		})
		done <- err
	}()

	select {
	case err := <-done:
		if err == nil {
			t.Fatal("expected error when no SSE client is connected")
		}
	case <-time.After(1 * time.Second):
		t.Fatal("requestDialog blocked instead of failing fast without SSE client")
	}
}

func TestNativeRPCServerCloseUnblocksSSEAndDialog(t *testing.T) {
	app := NewApp(t.TempDir(), "test")
	server, err := NewNativeRPCServer(app)
	if err != nil {
		t.Fatalf("NewNativeRPCServer failed: %v", err)
	}

	resp, reader := openTestSSEStream(t, server)
	defer func() { _ = resp.Body.Close() }()

	dialogErrCh := make(chan error, 1)
	go func() {
		_, err := server.MessageDialog(context.Background(), MessageDialogOptions{
			Type:    "question",
			Title:   "Confirm",
			Message: "Proceed?",
		})
		dialogErrCh <- err
	}()

	event := readNextSSEEvent(t, reader, 2*time.Second)
	if event.Name != "native:dialog" {
		t.Fatalf("expected native:dialog event, got %q", event.Name)
	}

	sseClosedCh := make(chan error, 1)
	go func() {
		for {
			if _, err := reader.ReadString('\n'); err != nil {
				sseClosedCh <- err
				return
			}
		}
	}()

	closeCtx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()
	if err := server.Close(closeCtx); err != nil {
		t.Fatalf("Close failed: %v", err)
	}
	// Closing twice and calling QuitApplication must remain safe via sync.Once.
	server.QuitApplication()
	_ = server.Close(closeCtx)

	select {
	case err := <-dialogErrCh:
		if err == nil {
			t.Fatal("expected pending requestDialog to fail on Close()")
		}
	case <-time.After(1 * time.Second):
		t.Fatal("pending requestDialog did not unblock on Close()")
	}

	select {
	case err := <-sseClosedCh:
		if err == nil {
			t.Fatal("expected SSE stream to terminate on Close()")
		}
	case <-time.After(1 * time.Second):
		t.Fatal("SSE handler did not terminate on Close()")
	}
}

func TestNativeRPCServerClearPendingUpdatePreventsReplayOnReconnect(t *testing.T) {
	app := NewApp(t.TempDir(), "1.9.7")
	server, err := NewNativeRPCServer(app)
	if err != nil {
		t.Fatalf("NewNativeRPCServer failed: %v", err)
	}
	SetRuntimeHost(app, server)
	defer func() {
		ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
		defer cancel()
		_ = server.Close(ctx)
	}()

	installerPath := filepath.Join(t.TempDir(), "setup.exe")
	if err := os.WriteFile(installerPath, []byte("installer"), 0o644); err != nil {
		t.Fatalf("write installer: %v", err)
	}
	if err := app.savePendingUpdate(UpdatePendingInfo{
		Version:       "2.0.0",
		InstallerPath: installerPath,
		PID:           12345,
		CreatedAt:     time.Now().Format(time.RFC3339),
	}); err != nil {
		t.Fatalf("savePendingUpdate failed: %v", err)
	}

	app.NotifyPendingAppUpdate()
	server.EmitRuntimeEvent("app:ready")

	// Initial SSE connection receives both app:update:pending and app:ready.
	resp1, reader1 := openTestSSEStream(t, server)
	ev1 := readNextSSEEvent(t, reader1, 2*time.Second)
	ev2 := readNextSSEEvent(t, reader1, 2*time.Second)
	_ = resp1.Body.Close()
	if ev1.Name != updatePendingEvent || ev2.Name != "app:ready" {
		t.Fatalf("initial SSE events = [%q, %q], want [%q, %q]", ev1.Name, ev2.Name, updatePendingEvent, "app:ready")
	}

	// Clearing pending update invalidates sticky cache and is idempotent on repeat calls.
	if err := app.ClearPendingAppUpdate(); err != nil {
		t.Fatalf("ClearPendingAppUpdate failed: %v", err)
	}
	if err := app.ClearPendingAppUpdate(); err != nil {
		t.Fatalf("repeat ClearPendingAppUpdate should be idempotent, got %v", err)
	}

	// Reconnected SSE client must NOT receive stale app:update:pending.
	resp2, reader2 := openTestSSEStream(t, server)
	defer func() { _ = resp2.Body.Close() }()
	reconnected := readNextSSEEvent(t, reader2, 2*time.Second)
	if reconnected.Name != "app:ready" {
		t.Fatalf("reconnected SSE first event = %q, want %q (stale %q must not replay)", reconnected.Name, "app:ready", updatePendingEvent)
	}
}
