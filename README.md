# Claude Code for TrueNAS

[Claude Code](https://docs.claude.com/en/docs/claude-code) in a browser terminal (ttyd + tmux),
running as a TrueNAS SCALE custom app, with the official
[TrueNAS MCP server](https://github.com/truenas/truenas-mcp) built in. Ask Claude about your pools,
datasets, snapshots, replication, shares and apps in plain language.

The TrueNAS counterpart of the [Claude Code Home Assistant add-on](https://github.com/Kokbo/claude-code-ha-addons).

- **Read-only by default** — the MCP server hides and refuses every tool that changes the NAS.
- **Verified TLS out of the box** — with host networking the app talks to the API on `localhost`
  and pins the NAS's own certificate.
- **Persistent** — Claude login, settings, MCP config, history and updates live in one dataset.
- **Self-updating** — Claude Code updates on restart; the image is rebuilt weekly.

Image: `ghcr.io/kokbo/claude-code-truenas:latest` (amd64)

## Install

### 1. Create a read-only API user

1. **Credentials → Users → Add**: username `claude-ro`, no shell, no SMB access, and give it the
   **read-only administrator** role (TrueNAS Access → *Read-Only Admin*; on older versions add it to
   the `builtin_readonly_administrators` group).
2. On that user's row, **View API Keys → Add API Key**, select `claude-ro`, save, and copy the key
   (it is shown only once).

### 2. Create a dataset for the app

**Datasets → your pool → Add Dataset**: `apps/claude-code`, preset *Generic*.

### 3. Install the app

**Apps → Discover Apps → ⋮ → Install via YAML**, name it `claude-code`, and paste
[`truenas-app.yaml`](truenas-app.yaml). Change:

- `tank` → your pool name
- `TTYD_PASSWORD` → a strong password for the web terminal
- `TRUENAS_API_KEY` → the key from step 1

Check the app's **Logs**: you should see `TrueNAS MCP: authenticated to localhost as claude-ro`.

### 4. Log in to Claude

Open `http://<nas-ip>:7681`, sign in with `TTYD_USER` / `TTYD_PASSWORD`, run `claude`, then `/login`.
Open the link, approve, and paste the code back into the terminal. The login is kept in `/data`.

Then ask, for example:

- *Show my pool layout and health. Can I go from 5 to 4 disks without losing data?*
- *Which datasets have no snapshot task or replication?*
- *Review my snapshot retention, scrub schedule and backups, and suggest improvements.*

## Configuration

| Variable | Default | Description |
|---|---|---|
| `TTYD_PASSWORD` | — | **Required.** Web terminal password. The app refuses to start without it. |
| `TTYD_USER` | `claude` | Web terminal username. |
| `TTYD_PORT` | `7681` | Web terminal port. |
| `TTYD_ALLOW_NO_AUTH` | `false` | Allow starting without a password (not recommended). |
| `TRUENAS_URL` | — | TrueNAS host. `localhost` with host networking (recommended), else a hostname or IP, or `wss://host:port`. Unset = no MCP server. |
| `TRUENAS_API_USER` | — | User that owns the API key. |
| `TRUENAS_API_KEY` | — | TrueNAS API key. |
| `TRUENAS_MCP_READ_ONLY` | `true` | Hide and refuse tools that change the NAS. When `true`, the remaining tools are pre-approved. |
| `TRUENAS_TLS_CA` | auto | PEM certificate to trust. Set automatically when `TRUENAS_URL` is `localhost`. |
| `TRUENAS_INSECURE` | `false` | Skip TLS verification. Last resort, LAN only. |
| `CLAUDE_MODEL` | Claude Code default | Default model, e.g. `claude-opus-5-5`. |
| `AUTO_UPDATE_CLAUDE` | `true` | Update Claude Code on every start (rolled back if it fails to run). |
| `SESSION_PERSISTENCE` | `true` | Keep the terminal in a tmux session that survives closing the tab. |
| `TERMINAL_THEME` | `dark` | `dark` or `light`. |
| `TERMINAL_FONT_SIZE` | `14` | Terminal font size. |
| `WORKDIR` | `/data/workspace` | Directory the terminal starts in. |
| `ENABLE_REMOTE_CONTROL` | `false` | Run `claude remote-control` so you can steer sessions from claude.ai or the Claude app. Anyone signed in to your Claude account can then control this container. |
| `REMOTE_CONTROL_NAME` | `TrueNAS` | Session name shown in Remote Control. |

## TLS options

TrueNAS only accepts API keys over encrypted connections (and revokes a key used over plain `ws://`).

- **Host networking + `TRUENAS_URL: localhost`** (default in `truenas-app.yaml`): the default TrueNAS
  certificate is issued for `localhost`, and over loopback the app pins it automatically. Fully verified, zero setup.
- **Custom HTTPS port** (System → General → GUI → Web Interface HTTPS Port, e.g. `444` when 443 is used by a
  reverse proxy): set `TRUENAS_URL: "localhost:444"`. Verification still works.
- **Web UI bound to one IP** (System → General → GUI → Web Interface IPv4 Address is not `0.0.0.0`): nothing
  listens on `localhost`, so the log shows `connection refused`. Set `TRUENAS_URL` to the NAS IP and
  `TRUENAS_INSECURE: "true"`. With host networking that connection stays inside the machine.
- **Your own certificate** (e.g. ACME for `nas.example.com`): set `TRUENAS_URL` to that name; it is verified
  against the public CAs.
- **Bridge networking** (no `network_mode: host`, add `ports: ["7681:7681"]`): set `TRUENAS_URL` to the NAS IP.
  The default certificate doesn't cover the IP, so either give TrueNAS a certificate that does, or set
  `TRUENAS_INSECURE: "true"`.

Run `truenas-cert <host>` in the terminal to see which names a certificate covers, and `truenas-check`
to re-test the connection.

## Persistent data (`/data`)

| Path | Contents |
|---|---|
| `claude/` | `~/.claude`: settings, `CLAUDE.md` (global instructions), sessions |
| `claude.json` | `~/.claude.json`: login and MCP server config |
| `npm-global/` | Claude Code updates |
| `workspace/` | Default working directory |
| `ssh/`, `gh/` | SSH keys and GitHub CLI login |
| `truenas-cert.pem` | Pinned TrueNAS certificate |

Edit `/data/claude/CLAUDE.md` to change Claude's standing instructions; it is only written when missing.

## Security notes

- Keep port 7681 on your LAN. The terminal is a root shell inside the container that holds your Claude
  login and the TrueNAS API key — don't port-forward it. For remote access use a VPN or an
  authenticating proxy such as Cloudflare Access.
- The container has no access to the TrueNAS host shell or ZFS; everything goes through the API key's permissions.
- Want Claude to make changes? Use a key with more rights and set `TRUENAS_MCP_READ_ONLY: "false"`.
  Claude will then ask before every TrueNAS tool call, and write tools support a dry run.
- The TrueNAS MCP server is a research preview from iXsystems.

## Updating

- **Claude Code**: restart the app (or run `claude-update` in the terminal).
- **Image** (base OS, ttyd, MCP server): *Apps → claude-code → Update* pulls the newest weekly build.
- **MCP server version**: bump `TRUENAS_MCP_VERSION` in the `Dockerfile`.

## Troubleshooting

- **App keeps restarting** → check the logs; usually `TTYD_PASSWORD` is not set.
- **`TrueNAS MCP could not connect`** → the log shows the reason. Check the API user, key and
  `TRUENAS_URL`; run `truenas-check` in the terminal after fixing.
- **`connection refused`** → the web UI uses another HTTPS port or is bound to one IP; see TLS options.
- **Port 7681 already in use** (host networking) → set `TTYD_PORT` to another port.
- **`claude` hangs** → the CPU lacks AVX (e.g. a VM with a generic CPU type); set the VM CPU type to `host`.
