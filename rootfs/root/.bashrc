export TERM=xterm-256color
export LANG=C.UTF-8
export PATH="/data/npm-global/bin:/root/.local/bin:$PATH"
export HISTFILE=/data/.bash_history
export HISTSIZE=10000
PS1='\[\033[1;36m\]claude-truenas\[\033[0m\]:\[\033[1;34m\]\w\[\033[0m\]\$ '

# `claude update` can't write to the image layer; install into the persisted prefix instead.
claude() {
    if [ "$1" = "update" ]; then
        echo "Updating Claude Code into /data/npm-global..."
        npm install -g @anthropic-ai/claude-code@latest \
            --prefix /data/npm-global --no-fund --no-audit 2>&1
        hash -r 2>/dev/null
        newbin=/data/npm-global/bin/claude
        if [ -x "$newbin" ] && timeout 30 "$newbin" --version </dev/null >/dev/null 2>&1; then
            echo "Done: $("$newbin" --version 2>/dev/null)"
        else
            echo "The new version does not run here — rolling back to the bundled version"
            rm -rf /data/npm-global && mkdir -p /data/npm-global
            hash -r 2>/dev/null
            echo "Now using: $(command claude --version 2>/dev/null)"
        fi
        return 0
    fi
    command claude "$@"
}

# Re-test the TrueNAS connection (authenticates once, then exits)
truenas-check() {
    local ca_env=()
    [ -z "$TRUENAS_TLS_CA" ] && [ -f /data/truenas-cert.pem ] \
        && [[ "$TRUENAS_URL" =~ ^(localhost|127\.0\.0\.1)(:[0-9]+)?$ ]] \
        && ca_env=(TRUENAS_TLS_CA=/data/truenas-cert.pem)
    env "${ca_env[@]}" timeout 30 truenas-mcp </dev/null
}

alias ll='ls -la'
alias c='claude'
alias cc='claude --continue'
alias claude-update='claude update'

[ -f /data/.update_notice ] && echo -e "\033[1;33m[UPDATE AVAILABLE]\033[0m Claude Code $(cat /data/.update_notice) — restart the app or run: claude-update"
