# syntax=docker/dockerfile:1

# Pinned release of the official TrueNAS MCP server (https://github.com/truenas/truenas-mcp).
# Bump this to pick up a newer version; the weekly CI rebuild does NOT change it.
ARG TRUENAS_MCP_VERSION=v0.0.7
ARG TTYD_VERSION=1.7.7

# ---------------------------------------------------------------------------
# Stage 1: build truenas-mcp from source (no prebuilt binaries are published)
# ---------------------------------------------------------------------------
FROM golang:1 AS mcp-build
ARG TRUENAS_MCP_VERSION
# go.mod may require a newer Go than the image ships; let Go fetch it.
ENV GOTOOLCHAIN=auto \
    CGO_ENABLED=0
RUN git clone --depth 1 --branch "${TRUENAS_MCP_VERSION}" \
        https://github.com/truenas/truenas-mcp /src
WORKDIR /src
RUN go build -trimpath \
        -ldflags "-s -w -X main.Version=${TRUENAS_MCP_VERSION}" \
        -o /out/truenas-mcp ./cmd/truenas-mcp \
    && /out/truenas-mcp --version

# ---------------------------------------------------------------------------
# Stage 2: runtime — Claude Code + ttyd web terminal + tmux
# ---------------------------------------------------------------------------
FROM node:24-slim

LABEL org.opencontainers.image.title="Claude Code for TrueNAS" \
      org.opencontainers.image.description="Claude Code CLI in a browser terminal, with the official TrueNAS MCP server" \
      org.opencontainers.image.source="https://github.com/Kokbo/claude-code-truenas-addon" \
      org.opencontainers.image.licenses="MIT"

ENV LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    TERM=xterm-256color \
    DISABLE_AUTOUPDATER=1 \
    # Safe default: the MCP server hides and refuses every tool that changes the NAS.
    TRUENAS_MCP_READ_ONLY=true

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        bash \
        bind9-dnsutils \
        ca-certificates \
        curl \
        gh \
        git \
        iputils-ping \
        jq \
        less \
        nano \
        openssh-client \
        openssl \
        procps \
        python3 \
        ripgrep \
        tmux \
        vim-tiny \
    && rm -rf /var/lib/apt/lists/*

# ttyd as a static binary (avoids libwebsockets packaging issues)
ARG TTYD_VERSION
ARG TARGETARCH
RUN case "${TARGETARCH:-amd64}" in \
        amd64) TTYD_ARCH="x86_64" ;; \
        arm64) TTYD_ARCH="aarch64" ;; \
        *) echo "Unsupported architecture: ${TARGETARCH}" >&2; exit 1 ;; \
    esac \
    && curl -fsSL --retry 5 --retry-delay 2 --retry-all-errors \
        "https://github.com/tsl0922/ttyd/releases/download/${TTYD_VERSION}/ttyd.${TTYD_ARCH}" \
        -o /usr/local/bin/ttyd \
    && chmod +x /usr/local/bin/ttyd \
    && ttyd --version

# Passthrough sudo: the container runs as root, but some install scripts call sudo.
RUN printf '#!/bin/sh\nexec "$@"\n' > /usr/local/bin/sudo && chmod +x /usr/local/bin/sudo

# Claude Code. The cache-bust arg makes CI pick up the latest release on every build.
ARG CLAUDE_CODE_CACHEBUST=dev
RUN echo "Build ${CLAUDE_CODE_CACHEBUST}: installing latest Claude Code" \
    && npm install -g @anthropic-ai/claude-code@latest --no-fund --no-audit \
    && claude --version

COPY --from=mcp-build /out/truenas-mcp /usr/local/bin/truenas-mcp

COPY rootfs/ /
RUN chmod +x /usr/local/bin/start-claude-truenas.sh /usr/local/bin/truenas-cert \
    && mkdir -p /data /root/.config /root/.local

ENV PATH="/data/npm-global/bin:/root/.local/bin:${PATH}"

VOLUME ["/data"]
WORKDIR /data
EXPOSE 7681

HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD curl -s -o /dev/null http://127.0.0.1:${TTYD_PORT:-7681}/ || exit 1

ENTRYPOINT []
CMD ["/usr/local/bin/start-claude-truenas.sh"]
