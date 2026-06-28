# Plowman

A local CLI context engine that converts codebases, databases, logs, and existing scripts into structured, AI-ready knowledge — so AI assistants reason instead of reading raw files.

---

## Spec

See `spec.md` for the full spec. Key facts:

- **Goal:** Turn raw engineering artifacts into structured JSON/Markdown context that AI coding assistants consume instead of reading raw files
- **User:** Software engineers, technical leads, and agency teams onboarding AI assistants to complex projects
- **Domain:** Developer tooling / CLI
- **v1 scope:** Repo scanner, SQL dump analyzer, log analyzer, plugin wrapper, dual JSON/Markdown output, `plowman doctor`
- **Out of scope:** Web UI, cloud hosting, auth, billing, auto-apply recommendations, Linux/Windows builds, live DB inspection

---

## Guardrails (project-specific)

### Always do
- Read `spec.md` before any implementation work
- Run `/verify-output` before marking tasks complete
- Keep changes scoped to v1 — do not add features not in the spec
- Before making domain-specific decisions: read `_knowledgebase/README.md` to find relevant files, then read those files
- Before starting a new domain or project type: read `_skills/README.md` and apply any relevant playbooks
- JSON to stdout, errors to stderr, non-zero exit on failure — same contract as foreman-tools

### Ask first
- Any new subcommand or output field not in the spec
- Any change to the JSON/Markdown output schema — downstream consumers depend on it
- Installing, upgrading, or removing dependencies or packages
- Any operation that writes files outside this project directory
- Any mid-project scope change — propose it, get sign-off, then update spec.md

### Never do
- Never write to a production database or live system
- Never send real messages, emails, or notifications to real users
- Never auto-apply a recommendation — Plowman diagnoses; user must approve any changes
- Never make network calls — local filesystem and subprocess only
- Skip the verifier before marking work done
- Add scope without updating spec.md and getting explicit sign-off first

---

## Tools & Resources

- **Repo:** https://github.com/michaelvgonzaga/plowman
- **Platform / runtime:** Zig 0.16 — single binary, macOS arm64
- **Key tools & services:** ripgrep (file scanning), fd (file discovery), jq (JSON processing); optional: tree-sitter (AST), sqlite3, mysql/psql CLIs
- **Data & storage:** Local files only — input artifacts and output reports on disk
- **Domain-specific requirements:** None identified

---

## How to execute

```bash
# setup
brew install zig ripgrep fd jq

# build
zig build -Doptimize=ReleaseSafe

# run / work
./zig-out/bin/plowman scan repo <path>
./zig-out/bin/plowman scan db <dump.sql>
./zig-out/bin/plowman scan log <file>
./zig-out/bin/plowman plugin install <manifest.yml>
./zig-out/bin/plowman doctor

# validate / test
zig build test
```

---

## Knowledgebase

Project knowledge: `knowledge/[topic].md`. Global: `_knowledgebase/[topic].md`.

---

## Decision log

| Date | Decision | Why |
|------|----------|-----|
| 2026-06-29 | Zig runtime | Single binary, no runtime deps, fast startup; matches foreman-tools precedent |
| 2026-06-29 | macOS arm64 only for v1 | Aligns with existing toolchain; Linux/Windows deferred to v2 |
| 2026-06-29 | Local-only in v1 | No cloud infrastructure needed; keep user artifacts on-machine |
| 2026-06-29 | Dual output: JSON + Markdown on every command | JSON for AI consumption, Markdown for human readability; one call serves both |
| 2026-06-29 | Plugin manifest approach (YAML) | Reliable and incremental; no auto-reverse-engineering of arbitrary scripts |
| 2026-06-29 | ripgrep + fd for file scanning | Best-in-class tools already exist; Plowman orchestrates, doesn't reimplement |
| 2026-06-29 | CLI-only in v1 | Fastest path to value; no UI infrastructure required |
| 2026-06-29 | M1 repo scanner is filesystem-only | Git history patterns deferred; filesystem summary validates core value proposition |
| 2026-06-29 | No manifest versioning in v1 | Adds complexity before the format is proven; v2 scope after first real plugin |
| 2026-06-29 | M1 complete — `plowman scan repo` working | Detects framework, maps directories, extracts deps, outputs Markdown + JSON |
| 2026-06-29 | `io` threaded through all Io.Dir/File ops — Zig 0.16 requires it | Zig 0.16 replaced std.fs with std.Io; all dir/file ops take io parameter |
| 2026-06-29 | Renamed from Zigger-CLI to Plowman | Name change; all binary, module, repo, and doc references updated |
| 2026-06-29 | v2: git history via `git log` subprocess | No new deps; three signals: hotspots, co-change pairs, stale dirs; auto-detected, silent fallback |
| 2026-06-29 | v2: 90-day window, 50-file per-commit cutoff | Recent enough to reflect active patterns; cutoff prevents mass-refactor commits distorting co-change scores |
