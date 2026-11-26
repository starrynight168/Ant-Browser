package proxy

import (
	"strings"

	"gopkg.in/yaml.v3"
)

type DnsDiagnosticSummary struct {
	HasConfig                  bool     `json:"hasConfig"`
	SourceFormat               string   `json:"sourceFormat"`
	EnhancedMode               string   `json:"enhancedMode"`
	NameserverCount            int      `json:"nameserverCount"`
	FallbackCount              int      `json:"fallbackCount"`
	ProxyServerNameserverCount int      `json:"proxyServerNameserverCount"`
	XrayServerCount            int      `json:"xrayServerCount"`
	Unsupported                []string `json:"unsupported"`
}

// parseDnsConfig 解析 DNS 配置，支持 Clash dns: YAML 块及逗号/换行分隔的列表。
// 复用 parseClashBridgeDNS，统一遵守 dns.enable: false 与多行解析规则。
// 返回 xray dns 配置 map，若无有效配置则返回 nil。
//
// 注意：xray dns.servers 支持 IP / IP:port / DoH（https://）/ localhost，
// 不支持 Clash 的 tls:// 格式（DoT），会被过滤并在配置构建时记录告警。
func parseDnsConfig(raw string) map[string]interface{} {
	cfg := parseClashBridgeDNS(raw)
	if !cfg.hasServers() {
		return nil
	}

	seen := make(map[string]struct{})
	servers := make([]interface{}, 0)
	appendList := func(items []string) {
		for _, item := range items {
			addr, ok := normalizeXrayDnsAddr(item)
			if !ok {
				continue
			}
			if _, exists := seen[addr]; exists {
				continue
			}
			seen[addr] = struct{}{}
			servers = append(servers, addr)
		}
	}

	appendList(cfg.Nameserver)
	// xray 没有"仅用于解析代理服务器域名"的独立配置，proxy-server-nameserver
	// 只能并入全局 servers；桥接只跑单节点，不会影响目标域名分流策略。
	appendList(cfg.ProxyServerNameserver)
	appendList(cfg.Fallback)
	appendList(cfg.DefaultNameserver)

	if len(servers) == 0 {
		return nil
	}
	return map[string]interface{}{"servers": servers}
}

// normalizeXrayDnsAddr 校验并归一化 xray dns.servers 地址。
// 支持 IP、IP:port、DoH（https://...）、localhost（可带 udp:// 前缀或 # 后缀），
// 过滤 xray 不支持的 tls://（DoT）与明显无效地址。
func normalizeXrayDnsAddr(s string) (string, bool) {
	value := strings.TrimSpace(s)
	if value == "" {
		return "", false
	}
	if strings.HasPrefix(strings.ToLower(value), "tls://") {
		return "", false
	}
	if idx := strings.IndexByte(value, '#'); idx >= 0 {
		value = strings.TrimSpace(value[:idx])
	}
	if strings.HasPrefix(strings.ToLower(value), "udp://") {
		value = strings.TrimSpace(value[len("udp://"):])
	}
	if strings.EqualFold(value, "localhost") {
		return "localhost", true
	}
	if convertSingBoxDNSServer(value, "check", "") == nil {
		return "", false
	}
	return value, true
}

func isXrayDnsAddr(s string) bool {
	_, ok := normalizeXrayDnsAddr(s)
	return ok
}

func buildDnsDiagnosticSummary(raw string) DnsDiagnosticSummary {
	raw = strings.TrimSpace(raw)
	if raw == "" {
		return DnsDiagnosticSummary{}
	}
	summary := DnsDiagnosticSummary{HasConfig: true, SourceFormat: "list"}
	type clashDns struct {
		Enable                *bool    `yaml:"enable"`
		EnhancedMode          string   `yaml:"enhanced-mode"`
		Nameserver            []string `yaml:"nameserver"`
		Fallback              []string `yaml:"fallback"`
		ProxyServerNameserver []string `yaml:"proxy-server-nameserver"`
	}
	type clashDnsWrapper struct {
		Dns clashDns `yaml:"dns"`
	}
	var wrapper clashDnsWrapper
	if err := yaml.Unmarshal([]byte(raw), &wrapper); err == nil &&
		(wrapper.Dns.Enable != nil || len(wrapper.Dns.Nameserver) > 0 || len(wrapper.Dns.Fallback) > 0 || len(wrapper.Dns.ProxyServerNameserver) > 0 || wrapper.Dns.EnhancedMode != "") {
		if wrapper.Dns.Enable != nil && !*wrapper.Dns.Enable {
			return DnsDiagnosticSummary{}
		}
		summary.SourceFormat = "clash"
		summary.EnhancedMode = strings.TrimSpace(wrapper.Dns.EnhancedMode)
		summary.NameserverCount = len(wrapper.Dns.Nameserver)
		summary.FallbackCount = len(wrapper.Dns.Fallback)
		summary.ProxyServerNameserverCount = len(wrapper.Dns.ProxyServerNameserver)
		allServers := append(append(append([]string{}, wrapper.Dns.Nameserver...), wrapper.Dns.Fallback...), wrapper.Dns.ProxyServerNameserver...)
		for _, server := range allServers {
			server = strings.TrimSpace(server)
			if server == "" {
				continue
			}
			if isXrayDnsAddr(server) {
				summary.XrayServerCount++
			} else {
				summary.Unsupported = append(summary.Unsupported, server)
			}
		}
		return summary
	}
	for _, server := range splitDNSList(raw) {
		summary.NameserverCount++
		if isXrayDnsAddr(server) {
			summary.XrayServerCount++
		} else {
			summary.Unsupported = append(summary.Unsupported, server)
		}
	}
	return summary
}
