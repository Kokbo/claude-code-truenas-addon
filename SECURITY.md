# Security policy

## Reporting a vulnerability

Please report vulnerabilities privately through
[GitHub's private vulnerability reporting](https://github.com/Kokbo/claude-code-truenas-addon/security/advisories/new)
(**Security → Report a vulnerability**). Don't open a public issue.

Useful to include: what is affected (image tag or commit), how to reproduce it, and the impact
(for example access to the web terminal, the Claude login or the TrueNAS API key).

## Scope

- This repository: the image build, the entrypoint and helper scripts, and the example app YAML.
- Problems in bundled upstream software — Claude Code, the TrueNAS MCP server, ttyd, or the base
  image — are best reported to that project. If the way this image uses them makes things worse,
  report that here.

## Supported versions

Only the latest image (`ghcr.io/kokbo/claude-code-truenas:latest`) gets fixes.
