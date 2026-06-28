# Zigger-CLI Spec

---

**The real goal:** Turn raw engineering artifacts (repos, SQL dumps, logs, scripts) into structured JSON/Markdown context that AI coding assistants consume instead of reading raw files — reducing token waste and improving AI accuracy.

**Who it's for:** Software engineers, technical leads, and agency teams who routinely onboard AI assistants to complex, unfamiliar projects.

**Domain:** Developer tooling / CLI

**Success in 30 days:** A developer can run `zigger scan repo <path>` on any codebase and hand the output directly to an AI assistant instead of pointing it at the raw source tree.

**How we'll measure it:** Output a valid, non-empty JSON/Markdown report from a real repo containing architecture type, dependency list, and key file paths — without the AI needing to read raw source files.

---

## Scope — v1 only

**In:**
- Repository scanner: detect framework, map folders, find routes/configs/dependencies, output architecture summary
- SQL dump analyzer: rank largest tables, detect missing indexes, flag cache/session/log tables, suggest bottlenecks
- Log analyzer: scan error patterns, detect repeat failures, summarize incidents
- Plugin wrapper: absorb existing CLIs (.sh, Python, Go, Node, Rust, binary) via a YAML manifest; expose as `zigger <domain> <command>` with help, validation, dry-run, and confirmation prompts
- Structured output: JSON (AI consumption) + Markdown (human readability), dual format on every command
- `zigger doctor`: dependency health check

**Out (explicitly):**
- Web UI, cloud hosting, auth, billing
- Auto-apply recommendations — Zigger diagnoses and recommends; user approves any changes
- Auto-reverse-engineering arbitrary scripts (manifest-first approach only)
- Linux/Windows builds
- Live database inspection (SQL dump files only in v1)
- Real-time collaboration

---

## The simplest version that delivers value

`zigger scan repo <path>` runs against an existing codebase and outputs a Markdown summary: detected framework, key directories, dependency list, and top-level architecture. An AI assistant receives that instead of thousands of raw files. That single command, working reliably, validates the core value proposition.

---

## Risks

- **Tree-sitter Zig bindings are immature** — may need regex/heuristic fallback for AST parsing; could limit accuracy of dependency graphs in M1
- **SQL dump format variation** — MySQL, PostgreSQL, and SQLite dumps differ significantly; the parser will miss edge cases on first iteration
- **Zig 0.16 is pre-1.0** — breaking API changes are possible during development; version must be pinned
- **Output quality hard to measure without AI validation loop** — reports may look structured but not actually reduce token usage in practice; manual spot-check required at M1
- **Plugin manifest design may not be expressive enough** — real-world CLIs have complex argument patterns; v1 manifest format will likely need revision after first real plugin

---

## Key decisions — requires explicit sign-off

- [x] Zig runtime — matches foreman-tools precedent; single binary, no runtime deps, fast startup
- [x] macOS arm64 only for v1 — aligns with existing toolchain; Linux/Windows deferred to v2
- [x] Local-only in v1 — no cloud, no auth, no remote storage
- [x] Dual output: JSON (AI consumption) + Markdown (human readability) on every command
- [x] Plugin manifest approach — YAML manifest wraps existing CLIs; no auto-reverse-engineering of scripts
- [x] ripgrep + fd for file scanning — leverage existing best-in-class tools, don't reimplement
- [x] CLI-only in v1 — no web UI or desktop app

---

## Open questions

- None.

---

## Milestones

| Milestone | What a user can do | Done when... |
|-----------|-------------------|--------------|
| M1 — Repo scanner | `zigger scan repo <path>` → Markdown/JSON report | Output contains detected framework, directory map, and dependency list for a real repo (filesystem-only, no git history) |
| M2 — DB + log scanners | `zigger scan db <dump.sql>` and `zigger scan log <file>` | Reports include table rankings, bottleneck flags, and top error patterns from real files |
| M3 — Plugin wrapper | `zigger plugin install <manifest.yml>` + `zigger <domain> <command>` | A real .sh or Python script is wrapped, discoverable, and invocable with help and dry-run |
| M4 — Hardened | `zigger doctor` + edge cases + error handling | Doctor passes on a clean machine; no unhandled panics on malformed input |
