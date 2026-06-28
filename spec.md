# Plowman Spec

---

**The real goal:** Turn raw engineering artifacts (repos, SQL dumps, logs, scripts) into structured JSON/Markdown context that AI coding assistants consume instead of reading raw files — reducing token waste and improving AI accuracy.

**Who it's for:** Software engineers, technical leads, and agency teams who routinely onboard AI assistants to complex, unfamiliar projects.

**Domain:** Developer tooling / CLI

**Success in 30 days:** A developer can run `plowman scan repo <path>` on any codebase and hand the output directly to an AI assistant instead of pointing it at the raw source tree.

**How we'll measure it:** Output a valid, non-empty JSON/Markdown report from a real repo containing architecture type, dependency list, and key file paths — without the AI needing to read raw source files.

---

## Scope — v1 only

**In:**
- Repository scanner: detect framework, map folders, find routes/configs/dependencies, output architecture summary
- SQL dump analyzer: rank largest tables, detect missing indexes, flag cache/session/log tables, suggest bottlenecks
- Log analyzer: scan error patterns, detect repeat failures, summarize incidents
- Plugin wrapper: absorb existing CLIs (.sh, Python, Go, Node, Rust, binary) via a YAML manifest; expose as `plowman <domain> <command>` with help, validation, dry-run, and confirmation prompts
- Structured output: JSON (AI consumption) + Markdown (human readability), dual format on every command
- `plowman doctor`: dependency health check

**Out (explicitly):**
- Web UI, cloud hosting, auth, billing
- Auto-apply recommendations — Plowman diagnoses and recommends; user approves any changes
- Auto-reverse-engineering arbitrary scripts (manifest-first approach only)
- Linux/Windows builds
- Live database inspection (SQL dump files only in v1)
- Real-time collaboration

---

## The simplest version that delivers value

`plowman scan repo <path>` runs against an existing codebase and outputs a Markdown summary: detected framework, key directories, dependency list, and top-level architecture. An AI assistant receives that instead of thousands of raw files. That single command, working reliably, validates the core value proposition.

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
- [x] Renamed from Zigger-CLI to Plowman

---

## Open questions

- None.

---

## Milestones — v1 (complete)

| Milestone | What a user can do | Done when... |
|-----------|-------------------|--------------|
| M1 — Repo scanner | `plowman scan repo <path>` → Markdown/JSON report | Output contains detected framework, directory map, and dependency list for a real repo (filesystem-only, no git history) |
| M2 — DB + log scanners | `plowman scan db <dump.sql>` and `plowman scan log <file>` | Reports include table rankings, bottleneck flags, and top error patterns from real files |
| M3 — Plugin wrapper | `plowman plugin install <manifest.yml>` + `plowman <domain> <command>` | A real .sh or Python script is wrapped, discoverable, and invocable with help and dry-run |
| M4 — Hardened | `plowman doctor` + edge cases + error handling | Doctor passes on a clean machine; no unhandled panics on malformed input |

---

## Scope — v2

**In:**
- Git history analysis added to `scan repo`: hotspots (churn), co-change pairs, stale modules
- Three signals, 90-day default window, graceful fallback when not in a git repo
- Output integrated into existing Markdown and JSON report formats

**Out (explicitly):**
- Per-author blame or attribution data
- Full commit message analysis or NLP on commit text
- Cross-repo history comparison
- Any changes to v1 commands outside of `scan repo`

---

## Risks — v2

- **Git not installed or repo has no history** — must degrade gracefully; omit section rather than error
- **Large repos with thousands of commits** — 90-day window limits data volume, but parsing could still be slow; may need a commit count cap
- **Co-change pairs produce false positives on mass-refactor commits** — a single commit touching 200 files skews all pair scores; need a per-commit file-count cutoff

---

## Key decisions — v2

- [x] Parse `git log` output via subprocess (same pattern as plugin runner) — no new deps, works anywhere git is installed
- [x] 90-day default window — recent enough to reflect current development patterns, short enough to be fast
- [x] Skip git history section silently when `git` is unavailable or path is not a repo — no flag required; auto-detected
- [x] Co-change cutoff: ignore commits touching more than 50 files — mass refactors distort pair scores
- [x] Top 10 hotspots, top 10 co-change pairs, all stale top-level dirs (no arbitrary cap on stale)

---

## Milestones — v2

| Milestone | What a user can do | Done when... |
|-----------|-------------------|--------------|
| M1 — Hotspots | `scan repo` on a git repo adds a hotspot table | Top 10 files by commit count in the last 90 days, from a real repo with 30+ commits |
| M2 — Co-change | Hotspot files show their co-change partners | Top 10 pairs with co-occurrence ≥ 2 commits, from a real repo |
| M3 — Stale modules | Report flags directories with no recent commits | Top-level dirs show last-touched date; stale (90+ days) flagged in output |
