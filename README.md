# Plowman

Turn raw engineering artifacts into structured context for AI coding assistants — so they reason instead of reading raw files.

Run `plowman scan repo <path>` on any codebase and hand the output directly to an AI assistant instead of pointing it at thousands of raw source files.

## What it does

- **Repo scanner** — detects framework, maps directories, extracts dependencies, surfaces git hotspots and co-change patterns
- **SQL dump analyzer** — ranks largest tables, flags missing indexes and cache/session tables, identifies bottlenecks
- **Log analyzer** — finds error patterns, detects repeat failures, summarizes incidents
- **Plugin wrapper** — wraps existing scripts (.sh, Python, Go, Node, Rust, binary) via a YAML manifest and exposes them as `plowman <domain> <command>`
- **Doctor** — checks that all required tools are installed and plugins are healthy

Every command outputs both Markdown (human-readable) and JSON (`--json`, for AI consumption).

## Install

Requires Zig 0.16, ripgrep, fd, and jq.

```bash
brew install zig ripgrep fd jq
git clone https://github.com/michaelvgonzaga/plowman
cd plowman
zig build -Doptimize=ReleaseSafe
cp zig-out/bin/plowman /usr/local/bin/
```

## Usage

```
plowman scan repo <path> [--json]        scan a repository
plowman scan db  <dump.sql> [--json]     analyze a SQL dump
plowman scan log <file> [--json]         analyze a log file
plowman plugin install <manifest.yml>    install a plugin
plowman plugin list                      list installed plugins
plowman <domain> help                    show plugin commands
plowman <domain> <command> [--dry-run]   run a plugin command
plowman doctor                           check dependencies and plugins
```

## Examples

### Scan a repo

```bash
plowman scan repo ~/projects/my-api
```

```
# Repo Analysis: ~/projects/my-api

## Overview
- **Framework:** Node.js

## Git History (47 commits, last 90 days)

### Hotspots
| File | Commits |
|------|---------|
| `src/routes/auth.js` | 18 |
| `src/middleware/index.js` | 11 |
...

### Co-change pairs
| File A | File B | Co-commits |
|--------|--------|------------|
| `src/routes/auth.js` | `src/middleware/index.js` | 9 |
...

### Stale modules (no commits in 90+ days)
| Directory | Last commit | Days ago |
|-----------|-------------|----------|
| `legacy/` | 2024-11-03 | 180 |
```

### JSON output (for AI assistants)

```bash
plowman scan repo ~/projects/my-api --json
```

### Wrap an existing script as a plugin

Create a manifest:

```yaml
domain: deploy
description: Deployment tools

commands:
  - name: staging
    description: Deploy to staging
    script: ./scripts/deploy.sh
    dry_run: true
    confirm: "Deploy to staging?"
    args:
      - name: branch
        description: Branch to deploy
        required: true
    env:
      - DEPLOY_ENV=staging
```

Install and run:

```bash
plowman plugin install deploy.yml
plowman deploy staging main
plowman deploy staging main --dry-run
```

### Check your setup

```bash
plowman doctor
```

## How it works

Plowman runs locally — no cloud, no auth, no network calls. It shells out to `ripgrep`, `fd`, and `git` for fast scanning and uses a custom YAML parser to load plugin manifests. Output goes to stdout; errors go to stderr.

Plugin manifests live at `~/.config/plowman/plugins/<domain>`.

## Platform

macOS arm64. Single binary, no runtime dependencies beyond the tools listed above.
