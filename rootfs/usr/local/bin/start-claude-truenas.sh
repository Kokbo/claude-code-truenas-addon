#!/bin/bash
# Entrypoint for Claude Code on TrueNAS.
# Everything is configured through environment variables (see README.md);
# everything that must survive updates lives under /data.
set -e

DATA=/data
NPM_GLOBAL_DIR="$DATA/npm-global"
SETTINGS_FILE="$DATA/claude/settings.json"

log()  { echo "[INFO] $*"; }
warn() { echo "[WARN] $*"; }
err()  { echo "[ERROR] $*"; }
truthy() { case "${1,,}" in 1|true|yes|on) return 0 ;; *) return 1 ;; esac; }

# ---------------------------------------------------------------------------
# Web terminal authentication — refuse to start an open root shell by accident
# ---------------------------------------------------------------------------
TTYD_USER="${TTYD_USER:-claude}"
TTYD_PORT="${TTYD_PORT:-7681}"
TTYD_AUTH=()
if [ -n "${TTYD_PASSWORD:-}" ]; then
    TTYD_AUTH=(--credential "${TTYD_USER}:${TTYD_PASSWORD}")
elif truthy "${TTYD_ALLOW_NO_AUTH:-false}"; then
    warn "TTYD_ALLOW_NO_AUTH=true: the web terminal has NO password."
    warn "Anyone who can reach port ${TTYD_PORT} gets a root shell with your Claude login and TrueNAS API key."
else
    err "TTYD_PASSWORD is not set. Set it in the app's environment variables."
    err "(To run without a password anyway, set TTYD_ALLOW_NO_AUTH=true — not recommended.)"
    sleep 30   # avoid a tight restart loop
    exit 1
fi

# ---------------------------------------------------------------------------
# Persistence: Claude login, settings, MCP config, updates, SSH/gh config
# ---------------------------------------------------------------------------
mkdir -p "$DATA/claude" "$DATA/config" "$DATA/gh" "$DATA/ssh" "$NPM_GLOBAL_DIR" \
         "$DATA/workspace" /root/.config
chmod 700 "$DATA/ssh"

link_dir() {  # link_dir <path-in-home> <persist-dir>
    if [ ! -L "$1" ]; then rm -rf "$1"; ln -s "$2" "$1"; fi
}
link_dir /root/.claude              "$DATA/claude"
link_dir /root/.config/claude-code  "$DATA/config"
link_dir /root/.config/gh           "$DATA/gh"
link_dir /root/.ssh                 "$DATA/ssh"
if [ ! -L /root/.claude.json ]; then
    [ -f "$DATA/claude.json" ] || { [ -s /root/.claude.json ] && cp /root/.claude.json "$DATA/claude.json" || touch "$DATA/claude.json"; }
    rm -f /root/.claude.json
    ln -s "$DATA/claude.json" /root/.claude.json
fi

# Global instructions for Claude — only written when missing, so edits survive restarts
if [ ! -f "$DATA/claude/CLAUDE.md" ]; then
    cp /etc/claude-truenas/CLAUDE.md "$DATA/claude/CLAUDE.md"
    log "Wrote default instructions to $DATA/claude/CLAUDE.md"
fi

export PATH="$NPM_GLOBAL_DIR/bin:$PATH"

# ---------------------------------------------------------------------------
# CPU check: Claude Code's runtime needs AVX on x86 and HANGS without it,
# which is why every claude call below is wrapped in timeout.
# ---------------------------------------------------------------------------
if [ "$(uname -m)" = "x86_64" ] && ! grep -qw avx /proc/cpuinfo 2>/dev/null; then
    warn "============================================================"
    warn "This CPU does not expose AVX, which Claude Code requires."
    warn "Claude Code will hang. If TrueNAS runs in a VM, set the VM CPU type to 'host'."
    warn "============================================================"
fi

# ---------------------------------------------------------------------------
# Claude Code updates: installed into a persisted npm prefix (the image layer is
# read-only to `claude update`). A version that fails to run is rolled back.
# ---------------------------------------------------------------------------
if truthy "${AUTO_UPDATE_CLAUDE:-true}"; then
    CURRENT_VER=$(timeout 30 claude --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1) || CURRENT_VER=""
    LATEST_VER=$(timeout 30 npm show @anthropic-ai/claude-code version 2>/dev/null) || LATEST_VER=""
    if [ -n "$LATEST_VER" ] && [ -n "$CURRENT_VER" ] && [ "$CURRENT_VER" != "$LATEST_VER" ]; then
        log "Updating Claude Code $CURRENT_VER -> $LATEST_VER"
        timeout 300 npm install -g "@anthropic-ai/claude-code@$LATEST_VER" \
            --prefix "$NPM_GLOBAL_DIR" --no-fund --no-audit >/dev/null 2>&1 || true
        hash -r
        if ! timeout 30 claude --version </dev/null >/dev/null 2>&1; then
            warn "Claude Code $LATEST_VER does not run here — rolling back to the bundled version"
            rm -rf "$NPM_GLOBAL_DIR"; mkdir -p "$NPM_GLOBAL_DIR"; hash -r
        fi
    fi
fi
log "Claude Code $(timeout 30 claude --version 2>/dev/null || echo 'version unknown')"
log "$(truenas-mcp --version 2>/dev/null || echo 'truenas-mcp missing')"

if [ -n "${CLAUDE_MODEL:-}" ]; then
    export ANTHROPIC_MODEL="$CLAUDE_MODEL"
    log "Default model: $CLAUDE_MODEL"
fi

# ---------------------------------------------------------------------------
# TrueNAS MCP server
# ---------------------------------------------------------------------------
[ -s "$SETTINGS_FILE" ] || echo '{}' > "$SETTINGS_FILE"
SETTINGS_TMP=$(mktemp)
set_allow() {   # set_allow add|remove <rule>
    local filter='.permissions.allow = ((.permissions.allow // []) - [$r])'
    [ "$1" = add ] && filter='.permissions.allow = (((.permissions.allow // []) + [$r]) | unique)'
    if jq --arg r "$2" "$filter" "$SETTINGS_FILE" > "$SETTINGS_TMP"; then
        cat "$SETTINGS_TMP" > "$SETTINGS_FILE"
    else
        warn "Could not update $SETTINGS_FILE (invalid JSON?) — permission rule '$2' not changed"
    fi
}

timeout 30 claude mcp remove truenas -s user >/dev/null 2>&1 || true

if [ -n "${TRUENAS_URL:-}" ]; then
    MCP_ENV='{}'

    # Host networking + TRUENAS_URL=localhost: pin the NAS's own certificate.
    # Over loopback nothing can sit in between, so trusting what answers is safe,
    # and the default TrueNAS certificate is issued for "localhost".
    if [ -z "${TRUENAS_TLS_CA:-}" ] && ! truthy "${TRUENAS_INSECURE:-false}" \
        && [[ "$TRUENAS_URL" =~ ^(localhost|127\.0\.0\.1)(:[0-9]+)?$ ]]; then
        if truenas-cert "$TRUENAS_URL" "$DATA/truenas-cert.pem" >/dev/null 2>&1; then
            export TRUENAS_TLS_CA="$DATA/truenas-cert.pem"
            MCP_ENV=$(jq -cn --arg ca "$TRUENAS_TLS_CA" '{TRUENAS_TLS_CA: $ca}')
            log "Pinned the TrueNAS certificate from $TRUENAS_URL"
        else
            warn "Could not read a certificate from $TRUENAS_URL (is the app using host networking?)"
        fi
    fi

    # Preflight: authenticate once and exit (stdin closed), so problems show up in the app log
    PREFLIGHT=$(timeout 30 truenas-mcp </dev/null 2>&1) || true
    if grep -q "Successfully authenticated" <<<"$PREFLIGHT"; then
        log "TrueNAS MCP: authenticated to $TRUENAS_URL as ${TRUENAS_API_USER:-?}"
    else
        warn "TrueNAS MCP could not connect yet. Output:"
        sed 's/^/[WARN]   /' <<<"$PREFLIGHT"
        if [[ "$TRUENAS_URL" =~ ^(localhost|127\.0\.0\.1) ]] && grep -q "connection refused" <<<"$PREFLIGHT"; then
            warn "Nothing listens on $TRUENAS_URL. Check System > General > GUI:"
            warn "- HTTPS port is not 443 (e.g. 444)? Set TRUENAS_URL=localhost:<port>"
            warn "- Web UI bound to one IP instead of 0.0.0.0? Set TRUENAS_URL to that IP and TRUENAS_INSECURE=true"
            warn "  (with host networking that connection never leaves the machine)"
        fi
        warn "Claude Code will still start; fix the settings and restart the app."
    fi

    MCP_JSON=$(jq -cn --argjson env "$MCP_ENV" \
        '{command: "truenas-mcp"} + (if $env == {} then {} else {env: $env} end)')
    timeout 30 claude mcp add-json truenas "$MCP_JSON" -s user >/dev/null 2>&1 \
        || warn "Could not register the TrueNAS MCP server"

    if truthy "${TRUENAS_MCP_READ_ONLY:-true}"; then
        # Write tools are hidden and refused by the server, so all remaining tools are safe to pre-approve
        set_allow add mcp__truenas
        log "TrueNAS MCP registered (read-only; tools pre-approved)"
    else
        set_allow remove mcp__truenas
        warn "TrueNAS MCP registered with WRITE access — Claude will ask before every tool call"
    fi
else
    set_allow remove mcp__truenas
    log "TRUENAS_URL not set — TrueNAS MCP server not configured"
fi

# ---------------------------------------------------------------------------
# Optional: Remote Control (steer sessions from claude.ai / the Claude app)
# ---------------------------------------------------------------------------
WORKDIR="${WORKDIR:-$DATA/workspace}"
[ -d "$WORKDIR" ] || { warn "WORKDIR '$WORKDIR' not found, using $DATA/workspace"; WORKDIR="$DATA/workspace"; }
cd "$WORKDIR"

if truthy "${ENABLE_REMOTE_CONTROL:-false}"; then
    RC_NAME="${REMOTE_CONTROL_NAME:-TrueNAS}"
    export CLAUDE_REMOTE_CONTROL_SESSION_NAME_PREFIX="$RC_NAME"
    tmux kill-session -t rc 2>/dev/null || true
    tmux new-session -d -s rc -c "$WORKDIR" \
        "while true; do claude remote-control --name ${RC_NAME@Q}; echo '[rc] exited, retrying in 30s'; sleep 30; done"
    log "Remote Control started in tmux session 'rc' (attach: tmux attach -t rc)"
fi

# ---------------------------------------------------------------------------
# Hourly update check — shows a notice in new shells
# ---------------------------------------------------------------------------
(set +e
while true; do
    IV=$(timeout 30 claude --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    LV=$(timeout 30 npm show @anthropic-ai/claude-code version 2>/dev/null)
    if [ -n "$LV" ] && [ -n "$IV" ] && [ "$IV" != "$LV" ]; then
        echo "$LV" > "$DATA/.update_notice"
    else
        rm -f "$DATA/.update_notice"
    fi
    sleep 3600
done) &

# ---------------------------------------------------------------------------
# Web terminal
# ---------------------------------------------------------------------------
if [ "${TERMINAL_THEME:-dark}" = "light" ]; then
    COLORS='background=#eff1f5,foreground=#4c4f69,cursor=#dc8a78'
else
    COLORS='background=#1e1e2e,foreground=#cdd6f4,cursor=#f5e0dc'
fi

if truthy "${SESSION_PERSISTENCE:-true}"; then
    SHELL_CMD=(tmux new-session -A -s claude)
else
    SHELL_CMD=(bash --login)
fi

log "Web terminal on port $TTYD_PORT (user: $TTYD_USER)"
# --debug 3 = errors and warnings only: at the default level ttyd logs the
# login credential (base64 user:password) to the app log.
exec ttyd --port "$TTYD_PORT" --writable --ping-interval 30 --max-clients 5 \
    --debug 3 \
    "${TTYD_AUTH[@]}" \
    -t fontSize="${TERMINAL_FONT_SIZE:-14}" \
    -t fontFamily=Monaco,Consolas,monospace \
    -t scrollback=20000 \
    -t "theme=$COLORS" \
    "${SHELL_CMD[@]}"
