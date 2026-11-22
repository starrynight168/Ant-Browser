package backend

import (
	"context"
	"crypto/rand"
	"crypto/subtle"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"net/http"
	"reflect"
	"strings"
	"sync"
	"time"
)

type NativeRPCServer struct {
	app          *App
	listener     net.Listener
	httpServer   *http.Server
	token        string
	quit         chan struct{}
	quitOnce     sync.Once
	eventMu      sync.Mutex
	nextEventID  uint64
	eventClients map[uint64]chan nativeRuntimeEvent
	dialogMu     sync.Mutex
	dialogs      map[string]chan nativeDialogResult
}

type nativeRuntimeEvent struct {
	Name string        `json:"name"`
	Args []interface{} `json:"args"`
}

type nativeDialogResult struct {
	value string
	err   string
}

type nativeInvokeRequest struct {
	Method string            `json:"method"`
	Args   []json.RawMessage `json:"args"`
}

func NewNativeRPCServer(app *App) (*NativeRPCServer, error) {
	if app == nil {
		return nil, fmt.Errorf("应用未初始化")
	}
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		return nil, err
	}
	secret := make([]byte, 32)
	if _, err := rand.Read(secret); err != nil {
		_ = listener.Close()
		return nil, err
	}
	server := &NativeRPCServer{
		app:          app,
		listener:     listener,
		token:        hex.EncodeToString(secret),
		quit:         make(chan struct{}),
		eventClients: make(map[uint64]chan nativeRuntimeEvent),
		dialogs:      make(map[string]chan nativeDialogResult),
	}
	mux := http.NewServeMux()
	mux.HandleFunc("/api/v1/invoke", server.handleInvoke)
	mux.HandleFunc("/api/v1/events", server.handleEvents)
	mux.HandleFunc("/api/v1/dialog/complete", server.handleDialogComplete)
	mux.HandleFunc("/api/v1/health", server.handleHealth)
	server.httpServer = &http.Server{
		Handler:           mux,
		ReadHeaderTimeout: 5 * time.Second,
		MaxHeaderBytes:    16 * 1024,
	}
	SetRuntimeHost(app, server)
	go func() {
		_ = server.httpServer.Serve(listener)
	}()
	return server, nil
}

func (s *NativeRPCServer) Address() string {
	return "http://" + s.listener.Addr().String()
}

func (s *NativeRPCServer) Token() string {
	return s.token
}

func (s *NativeRPCServer) QuitRequested() <-chan struct{} {
	return s.quit
}

func (s *NativeRPCServer) Close(ctx context.Context) error {
	if ctx == nil {
		ctx = context.Background()
	}
	return s.httpServer.Shutdown(ctx)
}

func (s *NativeRPCServer) EmitRuntimeEvent(name string, args ...interface{}) {
	event := nativeRuntimeEvent{Name: name, Args: args}
	s.eventMu.Lock()
	defer s.eventMu.Unlock()
	for _, client := range s.eventClients {
		select {
		case client <- event:
		default:
		}
	}
}

func (s *NativeRPCServer) QuitApplication() {
	s.quitOnce.Do(func() { close(s.quit) })
}

func (s *NativeRPCServer) OpenFileDialog(ctx context.Context, options OpenDialogOptions) (string, error) {
	return s.requestDialog(ctx, "openFile", options)
}

func (s *NativeRPCServer) OpenDirectoryDialog(ctx context.Context, options OpenDialogOptions) (string, error) {
	return s.requestDialog(ctx, "openDirectory", options)
}

func (s *NativeRPCServer) SaveFileDialog(ctx context.Context, options SaveDialogOptions) (string, error) {
	return s.requestDialog(ctx, "saveFile", options)
}

func (s *NativeRPCServer) MessageDialog(ctx context.Context, options MessageDialogOptions) (string, error) {
	return s.requestDialog(ctx, "message", options)
}

func (s *NativeRPCServer) requestDialog(ctx context.Context, kind string, options interface{}) (string, error) {
	if ctx == nil {
		ctx = context.Background()
	}
	requestID, err := newNativeRequestID()
	if err != nil {
		return "", err
	}
	result := make(chan nativeDialogResult, 1)
	s.dialogMu.Lock()
	s.dialogs[requestID] = result
	s.dialogMu.Unlock()
	defer func() {
		s.dialogMu.Lock()
		delete(s.dialogs, requestID)
		s.dialogMu.Unlock()
	}()
	s.EmitRuntimeEvent("native:dialog", map[string]interface{}{
		"requestId": requestID,
		"kind":      kind,
		"options":   options,
	})
	select {
	case response := <-result:
		if response.err != "" {
			return "", fmt.Errorf("%s", response.err)
		}
		return response.value, nil
	case <-ctx.Done():
		return "", ctx.Err()
	}
}

func newNativeRequestID() (string, error) {
	value := make([]byte, 16)
	if _, err := rand.Read(value); err != nil {
		return "", err
	}
	return hex.EncodeToString(value), nil
}

func (s *NativeRPCServer) handleHealth(w http.ResponseWriter, r *http.Request) {
	if !s.authorize(w, r) {
		return
	}
	if r.Method != http.MethodGet {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	_, _ = io.WriteString(w, `{"ready":true}`)
}

func (s *NativeRPCServer) handleInvoke(w http.ResponseWriter, r *http.Request) {
	if !s.authorize(w, r) {
		return
	}
	if r.Method != http.MethodPost {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	var request nativeInvokeRequest
	if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 32<<20)).Decode(&request); err != nil {
		s.writeInvokeResult(w, nil, fmt.Errorf("请求格式错误: %w", err))
		return
	}
	value, err := invokeBackendMethod(s.app, request.Method, request.Args)
	s.writeInvokeResult(w, value, err)
}

func (s *NativeRPCServer) writeInvokeResult(w http.ResponseWriter, value interface{}, err error) {
	w.Header().Set("Content-Type", "application/json")
	if err != nil {
		_ = json.NewEncoder(w).Encode(map[string]interface{}{"error": err.Error()})
		return
	}
	if _, marshalErr := json.Marshal(value); marshalErr != nil {
		_ = json.NewEncoder(w).Encode(map[string]interface{}{"error": marshalErr.Error()})
		return
	}
	_ = json.NewEncoder(w).Encode(map[string]interface{}{"value": value})
}

func invokeBackendMethod(app *App, methodName string, rawArgs []json.RawMessage) (value interface{}, err error) {
	defer func() {
		if recovered := recover(); recovered != nil {
			err = fmt.Errorf("后端方法执行失败: %v", recovered)
		}
	}()
	if app == nil || strings.TrimSpace(methodName) == "" {
		return nil, fmt.Errorf("后端方法名称无效")
	}
	method := reflect.ValueOf(app).MethodByName(methodName)
	if !method.IsValid() {
		return nil, fmt.Errorf("找不到后端方法: %s", methodName)
	}
	methodType := method.Type()
	if methodType.NumIn() != len(rawArgs) {
		return nil, fmt.Errorf("后端方法 %s 参数数量不匹配", methodName)
	}
	arguments := make([]reflect.Value, methodType.NumIn())
	for index := range arguments {
		argument := reflect.New(methodType.In(index))
		if err := json.Unmarshal(rawArgs[index], argument.Interface()); err != nil {
			return nil, fmt.Errorf("后端方法 %s 第 %d 个参数无效: %w", methodName, index+1, err)
		}
		arguments[index] = argument.Elem()
	}
	results := method.Call(arguments)
	if len(results) == 0 {
		return nil, nil
	}
	last := len(results) - 1
	errorType := reflect.TypeOf((*error)(nil)).Elem()
	if results[last].Type().Implements(errorType) {
		if !reflectValueIsNil(results[last]) {
			return nil, results[last].Interface().(error)
		}
		results = results[:last]
	}
	if len(results) == 0 {
		return nil, nil
	}
	if len(results) == 1 {
		return results[0].Interface(), nil
	}
	values := make([]interface{}, len(results))
	for index, result := range results {
		values[index] = result.Interface()
	}
	return values, nil
}

func reflectValueIsNil(value reflect.Value) bool {
	switch value.Kind() {
	case reflect.Chan, reflect.Func, reflect.Interface, reflect.Map, reflect.Pointer, reflect.Slice:
		return value.IsNil()
	default:
		return false
	}
}

func (s *NativeRPCServer) handleEvents(w http.ResponseWriter, r *http.Request) {
	if !s.authorize(w, r) {
		return
	}
	if r.Method != http.MethodGet {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	flusher, ok := w.(http.Flusher)
	if !ok {
		http.Error(w, "streaming unsupported", http.StatusInternalServerError)
		return
	}
	client := make(chan nativeRuntimeEvent, 256)
	s.eventMu.Lock()
	s.nextEventID++
	clientID := s.nextEventID
	s.eventClients[clientID] = client
	s.eventMu.Unlock()
	defer func() {
		s.eventMu.Lock()
		delete(s.eventClients, clientID)
		s.eventMu.Unlock()
	}()
	w.Header().Set("Content-Type", "text/event-stream")
	w.Header().Set("Cache-Control", "no-cache")
	w.Header().Set("X-Accel-Buffering", "no")
	flusher.Flush()
	for {
		select {
		case <-r.Context().Done():
			return
		case event := <-client:
			payload, err := json.Marshal(event)
			if err != nil {
				continue
			}
			if _, err := fmt.Fprintf(w, "data: %s\n\n", payload); err != nil {
				return
			}
			flusher.Flush()
		}
	}
}

func (s *NativeRPCServer) handleDialogComplete(w http.ResponseWriter, r *http.Request) {
	if !s.authorize(w, r) {
		return
	}
	if r.Method != http.MethodPost {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	var request struct {
		RequestID string `json:"requestId"`
		Value     string `json:"value"`
		Error     string `json:"error"`
	}
	if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 64*1024)).Decode(&request); err != nil {
		http.Error(w, "invalid request", http.StatusBadRequest)
		return
	}
	s.dialogMu.Lock()
	result := s.dialogs[request.RequestID]
	s.dialogMu.Unlock()
	if result == nil {
		http.Error(w, "dialog request not found", http.StatusNotFound)
		return
	}
	select {
	case result <- nativeDialogResult{value: request.Value, err: request.Error}:
	default:
	}
	w.WriteHeader(http.StatusNoContent)
}

func (s *NativeRPCServer) authorize(w http.ResponseWriter, r *http.Request) bool {
	provided := strings.TrimPrefix(r.Header.Get("Authorization"), "Bearer ")
	if len(provided) != len(s.token) || subtle.ConstantTimeCompare([]byte(provided), []byte(s.token)) != 1 {
		http.Error(w, "unauthorized", http.StatusUnauthorized)
		return false
	}
	return true
}
