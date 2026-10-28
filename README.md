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
- **Remote Control** — starts automatically, so you can steer sessions from claude.ai/code or the Claude app.

Image: `ghcr.io/kokbo/claude-code-truenas:latest` (amd64)

## Install

### 1. Make sure the image is public

New GitHub packages can start out private, and TrueNAS then can't pull the image. On GitHub, go to
your profile → **Packages** → `claude-code-truenas` → **Package settings** → **Change visibility** →
**Public**.

### 2. Look up your pool name and HTTPS port

- **Datasets**: the top-level name is your pool (for example `StoragePool`). Paths are case-sensitive.
- **System → General → GUI → Settings**: note the **Web Interface HTTPS Port** (443 by default; often
  444 when 443 is used by a reverse proxy) and check that **Web Interface IPv4 Address** is `0.0.0.0`.

### 3. Create a read-only API user

1. **Credentials → Users → Add** (or edit an existing user), username `claude-ro`.
2. Under **Allow Access**, tick **TrueNAS Access** and pick **Readonly Admin** in the dropdown that
   appears. Leave SMB, Shell and SSH access unticked.
3. **Disable Password** can stay ticked: the API key doesn't use the password. If Save insists on a
   password, untick it and set a long random one you never use.
4. Save.

On older TrueNAS versions without that option: **Credentials → Groups → Add**, select the
**Read-Only Administrator** privilege, save, and add `claude-ro` under **Members**.

### 4. Create the API key

1. In **Credentials → Users**, click the `claude-ro` **row itself** (not the edit pencil). In the details
   panel, the **Access** card has a **View API Keys** link.
   Alternative: top-right user icon → **My API Keys**.
2. **Add API Key**, give it a name, and make sure **Username** is `claude-ro` (not your admin account).
3. Save and copy the key immediately; it is shown only once.

### 5. Create a dataset for the app

1. **Datasets** → click your pool → **Add Dataset**: name `apps`, preset *Generic*.
2. Click `apps` → **Add Dataset**: name `claude-code`, preset *Generic*.

Don't add a share to it, and don't reuse a dataset that is shared over SMB: this folder holds your
Claude login and the TrueNAS API key.

### 6. Install the app

**Apps → Discover Apps → ⋮ → Install via YAML**, name it `claude-code`, and paste
[`truenas-app.yaml`](truenas-app.yaml). Change:

- `StoragePool` → your pool name (in the volume paths)
- `TTYD_PASSWORD` → a strong password for the web terminal (keep the quotes)
- `TRUENAS_URL` → `localhost` if your HTTPS port is 443, otherwise `localhost:<port>` (e.g. `localhost:444`)
- `TRUENAS_API_KEY` → the key from step 4 (keep the quotes)

### 7. Check the logs

**Apps → claude-code → Logs** should show:

```
[INFO] Pinned the TrueNAS certificate from localhost:444
[INFO] TrueNAS MCP: authenticated to localhost:444 as claude-ro
[INFO] Remote Control server started as 'TrueNAS' (tmux session 'rc'; ...)
```

A `connection refused` warning means the port in `TRUENAS_URL` is wrong; see [TLS options](#tls-options).

### 8. Log in to Claude

1. Open `http://<nas-ip>:7681` and sign in with `TTYD_USER` / `TTYD_PASSWORD`.
2. Run `truenas-check`; it should end with `Successfully authenticated with TrueNAS middleware`.
3. Run `claude`, then `/login`. Open the link, approve, and paste the code back into the terminal.
   The login is kept in `/data`.
4. Within 30 seconds the Remote Control server picks up the login. The **TrueNAS** session then appears
   in claude.ai/code and in the Claude app.

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
| `ENABLE_REMOTE_CONTROL` | `true` | Start a Remote Control server on every start (see below). |
| `REMOTE_CONTROL_NAME` | `TrueNAS` | Session name shown in claude.ai/code and the Claude app. |
| `REMOTE_CONTROL_PERMISSION_MODE` | Claude Code default | Permission mode for sessions started remotely: `default`, `acceptEdits` or `plan`. |

## Remote Control

With `ENABLE_REMOTE_CONTROL` on (the default), the app runs `claude remote-control` on every start, so
you can view and steer sessions from **claude.ai/code** or the **Claude app** without opening the
terminal. Requires a claude.ai Pro, Max, Team or Enterprise subscription (API keys are not supported).

- The server runs in its own detached tmux session `rc`, separate from the terminal session.
  Attach with `claude-rc` (or `tmux attach -t rc`); detach with Ctrl-b d.
- If it exits — for example before your first `/login` — it restarts after 30 seconds.
- `REMOTE_CONTROL_PERMISSION_MODE` sets how remote sessions ask for permission. `bypassPermissions`
  and `auto` are deliberately not offered.
- Anyone who can sign in to your Claude account can control this container. With the read-only API
  key the NAS itself stays read-only. Set `ENABLE_REMOTE_CONTROL: "false"` to turn it off.

## TLS options

TrueNAS only accepts API keys over encrypted connections (and revokes a key used over plain `ws://`).

- **Host networking + `TRUENAS_URL: localhost`** (or `localhost:<port>`, as in `truenas-app.yaml`): the default TrueNAS
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
