ARG BUILDER_BASE_IMAGE=swr.cn-north-4.myhuaweicloud.com/ddn-k8s/docker.io/library/golang:1.25-bookworm
FROM ${BUILDER_BASE_IMAGE}

RUN sed -i 's|http://deb.debian.org|https://deb.debian.org|g' /etc/apt/sources.list.d/debian.sources \
  && apt-get update -o Acquire::Retries=8 -o Acquire::https::Timeout=60 \
  && apt-get install -y --fix-missing --no-install-recommends \
    -o Acquire::Retries=8 -o Acquire::https::Timeout=60 \
    build-essential \
    ca-certificates \
    curl \
    dpkg-dev \
    git \
    gnupg \
    libayatana-appindicator3-dev \
    libgtk-3-dev \
    libwebkit2gtk-4.0-dev \
    patchelf \
    pkg-config \
    python3 \
    tar \
  && rm -rf /var/lib/apt/lists/*

ARG FLUTTER_VERSION=3.50.0
RUN git clone --depth 1 --branch "$FLUTTER_VERSION" https://github.com/flutter/flutter.git /opt/flutter \
  && git config --global --add safe.directory /opt/flutter \
  && /opt/flutter/bin/flutter config --no-analytics --enable-web \
  && /opt/flutter/bin/flutter precache --web

ENV GOPROXY="https://goproxy.cn,direct" \
    GOSUMDB="sum.golang.google.cn" \
    PATH="/root/go/bin:/opt/flutter/bin:${PATH}"

RUN go install github.com/wailsapp/wails/v2/cmd/wails@v2.12.0 \
  && ln -sf /root/go/bin/wails /usr/local/bin/wails
WORKDIR /workspace
