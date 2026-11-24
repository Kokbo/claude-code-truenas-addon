# syntax=docker/dockerfile:1@sha256:572cebbc2b15e6f84c077742952674889cb63cd5e9b80abdffcbe587b6f19183

# Pinned versions. Renovate proposes updates via the "# renovate:" comments;
# the weekly CI rebuild does NOT change them.

# Official TrueNAS MCP server (https://github.com/truenas/truenas-mcp). Upstream
# tags can be moved, so the build also checks the tag still points to this commit.
# renovate: datasource=github-tags depName=truenas/truenas-mcp
ARG TRUENAS_MCP_VERSION=v0.0.7
ARG TRUENAS_MCP_COMMIT=e5a2d27fe61006847f1e2715d6349cedef0089df

# ttyd static binary. On a version bump, copy both checksums from the
# release's SHA256SUMS; the build fails until they match.
# renovate: datasource=github-releases depName=tsl0922/ttyd
ARG TTYD_VERSION=1.7.7
ARG TTYD_SHA256_AMD64=8a217c968aba172e0dbf3f34447218dc015bc4d5e59bf51db2f2cd12b7be4f55
ARG TTYD_SHA256_ARM64=b38acadd89d1d396a0f5649aa52c539edbad07f4bc7348b27b4f4b7219dd4165

# ---------------------------------------------------------------------------
# Stage 1: build truenas-mcp from source (no prebuilt binaries are published)
# ---------------------------------------------------------------------------
FROM golang:1@sha256:3102e2c7eeee6e16de01ca3f35c56434696f70702a30b3d564b0244560981bb0 AS mcp-build
ARG TRUENAS_MCP_VERSION
ARG TRUENAS_MCP_COMMIT
# go.mod may require a newer Go than the image ships; let Go fetch it.
ENV GOTOOLCHAIN=auto \
    CGO_ENABLED=0
RUN git clone --depth 1 --branch "${TRUENAS_MCP_VERSION}" \
        https://github.com/truenas/truenas-mcp /src \
    && actual="$(git -C /src rev-parse HEAD)" \
    && if [ "${actual}" != "${TRUENAS_MCP_COMMIT}" ]; then \
        echo "truenas-mcp ${TRUENAS_MCP_VERSION} is commit ${actual}, expected ${TRUENAS_MCP_COMMIT}" >&2; \
        exit 1; \
    fi
WORKDIR /src
RUN go build -trimpath \
        -ldflags "-s -w -X main.Version=${TRUENAS_MCP_VERSION}" \
        -o /out/truenas-mcp ./cmd/truenas-mcp \
    && /out/truenas-mcp --version

# ---------------------------------------------------------------------------
# Stage 2: runtime — Claude Code + ttyd web terminal + tmux
# ---------------------------------------------------------------------------
FROM node:24-slim@sha256:873f586f3794f52281bd039bf02c048a0be08fde619338f9941bad1eb6b34530

LABEL org.opencontainers.image.title="Claude Code for TrueNAS" \
      org.opencontainers.image.description="Claude Code CLI in a browser terminal, with the official TrueNAS MCP server" \
      org.opencontainers.image.source="https://github.com/Kokbo/claude-code-truenas-addon" \
      org.opencontainers.image.licenses="MIT"

ENV LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    TERM=xterm-256color \
    DISABLE_AUTOUPDATER=1 \
    # Safe default: the MCP server hides and refuses every tool that changes the NAS.
    TRUENAS_MCP_READ_ONLY=true \
    # Claude Code's postinstall swaps a placeholder for the native binary; npm is
    # moving to running only allow-listed install scripts. An env var (not an
    # npmrc) also covers installs with --prefix /data/npm-global and `claude update`.
    npm_config_allow_scripts=@anthropic-ai/claude-code

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
ARG TTYD_SHA256_AMD64
ARG TTYD_SHA256_ARM64
ARG TARGETARCH
RUN case "${TARGETARCH:-amd64}" in \
        amd64) TTYD_ARCH="x86_64"; TTYD_SHA256="${TTYD_SHA256_AMD64}" ;; \
        arm64) TTYD_ARCH="aarch64"; TTYD_SHA256="${TTYD_SHA256_ARM64}" ;; \
        *) echo "Unsupported architecture: ${TARGETARCH}" >&2; exit 1 ;; \
    esac \
    && curl -fsSL --retry 5 --retry-delay 2 --retry-all-errors \
        "https://github.com/tsl0922/ttyd/releases/download/${TTYD_VERSION}/ttyd.${TTYD_ARCH}" \
        -o /usr/local/bin/ttyd \
    && printf '%s  %s\n' "${TTYD_SHA256}" /usr/local/bin/ttyd > /tmp/ttyd.sha256 \
    && sha256sum -c /tmp/ttyd.sha256 \
    && rm /tmp/ttyd.sha256 \
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

# Shell form on purpose: ${TTYD_PORT} must expand at run time.
# hadolint ignore=DL3025
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD curl -s -o /dev/null http://127.0.0.1:${TTYD_PORT:-7681}/ || exit 1

ENTRYPOINT []
CMD ["/usr/local/bin/start-claude-truenas.sh"]
