#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODE="${1:-stable}"

usage() {
  cat <<'EOF'
Usage:
  ./scripts/dev.sh [stable|live|help]

All modes now build the Flutter web UI through Wails.
EOF
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "[ERROR] Missing required command: $1" >&2
    exit 1
  fi
}

case "$MODE" in
  help|-h|--help)
    usage
    exit 0
    ;;
  stable|live)
    ;;
  *)
    echo "[ERROR] Unsupported mode: $MODE" >&2
    usage >&2
    exit 1
    ;;
esac

require_cmd flutter
require_cmd go
require_cmd wails

if [[ -n "${DEV_PROXY_URL:-}" ]]; then
  export HTTP_PROXY="$DEV_PROXY_URL"
  export HTTPS_PROXY="$DEV_PROXY_URL"
  export http_proxy="$DEV_PROXY_URL"
  export https_proxy="$DEV_PROXY_URL"
fi

if [[ -n "${DEV_NO_PROXY:-}" ]]; then
  export NO_PROXY="$DEV_NO_PROXY"
  export no_proxy="$DEV_NO_PROXY"
fi

if [[ -n "${DEV_GOPROXY:-}" ]]; then
  export GOPROXY="$DEV_GOPROXY"
elif [[ -z "${GOPROXY:-}" ]]; then
  export GOPROXY="https://goproxy.cn,direct"
fi

WAILS_BUILD_TAGS=()
if command -v pkg-config >/dev/null 2>&1 && ! pkg-config --exists webkit2gtk-4.0 && pkg-config --exists webkit2gtk-4.1; then
  WAILS_BUILD_TAGS=(-tags webkit2_41)
fi

cd "$ROOT_DIR"
exec wails dev "${WAILS_BUILD_TAGS[@]}"
