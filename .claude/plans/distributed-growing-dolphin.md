# Review: Rust `sq` CLI Rewrite Plan

## Overall Assessment

The plan is **well-structured and thorough** — it correctly identifies the distribution friction problem, proposes a reasonable approach, and demonstrates solid understanding of the existing Ruby implementation. Below are the remaining issues, resolved items, and an expanded analysis of the prime command and Magnus question.

---

## Resolved Issues

### ~~1. `transcript` source type missing~~ → Resolved

The plan's `Source` struct uses `type_: String` (not an enum), so transcript sources round-trip through serde without special handling. The Rust CLI doesn't need to validate source types — it just reads/writes them. Only `sq add` constrains what types it creates, but existing items with `transcript` sources will deserialize and serialize correctly. Metadata can carry any additional type semantics.

### ~~9. `claim` semantics may not be needed~~ → Confirmed: defer

`claim` is only used by the Ruby TUI, not by any `sq` subcommand. Drop from Phase 1 scope.

### ~~11. Config loading / YAML~~ → Resolved: no YAML needed

Every `sq` subcommand only uses `queue_path`. The precedence chain is fully expressible without YAML:

1. `--queue` / `-q` CLI flag (highest)
2. `SIFT_QUEUE_PATH` env var
3. `.sift/queue.jsonl` default

No subcommand accesses agent settings, concurrency, dry mode, or worktree config. The one edge case — `sq show` creating a `Config.new` for `worktree_base_branch` — uses the hardcoded default (`"main"`), not a loaded YAML value. **Drop `serde_yaml` from deps entirely.**

### ~~Suggestion C: Missing `serde_yaml` dependency~~ → Withdrawn

No longer needed per above.

---

## Open Issues

### 2. `sq edit` flags are incomplete

The plan's edit command section only mentions `--set-status` and `--set-blocked-by`. The actual Ruby implementation supports:
- `--set-status STATUS`
- `--set-title TITLE`
- `--set-metadata JSON`
- `--set-blocked-by IDS`
- `--add-diff PATH` (repeatable)
- `--add-file PATH` (repeatable)
- `--add-text STRING` (repeatable)
- `--add-directory PATH` (repeatable)
- `--add-transcript PATH` (repeatable)
- `--rm-source INDEX` (repeatable, 0-based)

The `--rm-source` behavior is notably tricky — indices are sorted in reverse before deletion to preserve correctness. This must be replicated exactly.

### 3. `sq list` jq integration details are slightly off

The actual Ruby wraps filter expressions as:
```ruby
jq_filter(items, "[.[] | #{options[:filter]}]")
```
And sorting uses:
```ruby
jq_filter(items, "sort_by(#{path} // infinite)")
```
Note the `// infinite` fallback for null sort keys. The `-e` flag is also passed to jq. These details matter for parity.

### 4. `sq prime` — Implementation approach (expanded)

`sq prime` dynamically introspects all registered subcommands via Ruby's `OptionParser` to generate flag documentation. This is non-trivial to port. Three viable approaches:

| Approach | How | Maintenance | Risk |
|----------|-----|-------------|------|
| **A: Runtime clap introspection** | `Command::get_subcommands()` + `Arg::get_long()`/`get_help()`/`get_value_names()` | Low — flags auto-update | clap doesn't expose arg hints as cleanly as OptionParser |
| **B: build.rs codegen** | Define flags in a data file, generate prime string at compile time | Medium — two artifacts to sync | Drift between spec and code |
| **C: Shared schema** | Single TOML/JSON spec drives both Rust clap and Ruby OptionParser | High upfront, low ongoing | Schema complexity |

**Recommendation: Approach A (runtime clap introspection).** It mirrors the Ruby design, keeps a single source of truth, and self-updates when flags change. The main gap — clap doesn't expose argument type hints ("PATH", "STRING") like OptionParser's `.arg` — is solved by using `Arg::value_name("PATH")` in the clap builder and reading it back via `Arg::get_value_names()`.

This means using clap's builder API or derive with `#[arg(value_name = "PATH")]` and introspecting the built `Command`. The plan should add a design section for this.

### 5. `--system-prompt` flag in CLAUDE.md

The CLAUDE.md examples show `sq add --system-prompt prompts/sec.md`. Verify whether this flag exists in the actual `add` implementation before starting — it may only be documented aspirationally. If it exists, it likely stores the path in metadata.

### 6. JSON output format: `pretty_generate` vs compact

`sq list --json` uses `JSON.pretty_generate` (indented). JSONL on disk is compact (one line per item). Rust's `serde_json` defaults to compact — use `serde_json::to_string_pretty` for CLI output paths.

### 7. `to_h` field omission rules need exact replication

Ruby's `Item#to_h` uses `.compact` and conditional inclusion:
- `title` omitted when nil
- `worktree` omitted when nil
- `blocked_by` omitted when empty
- `errors` omitted when empty
- `session_id` is always included (even when nil)

Requires careful `#[serde(skip_serializing_if = "...")]` with different predicates per field.

### 8. Timestamp format — low risk (expanded)

Timestamps are **opaque strings** in the Ruby codebase:
- Generated via `Time.now.utc.iso8601(3)` → `"2026-03-02T12:34:56.789Z"`
- Stored as strings in JSONL, never parsed back into Time objects
- Displayed as-is in `sq show` and `sq list`
- Sorted by jq (lexicographic string comparison), not by Ruby
- Never compared, calculated, or parsed by Ruby code

This means the Rust CLI just needs to:
1. Generate ISO 8601 strings with millisecond precision on `push`/`update` — `chrono::Utc::now().format("%Y-%m-%dT%H:%M:%S%.3fZ")` or equivalent
2. Preserve existing timestamp strings on read/write round-trips

Low risk as long as an explicit format string is used rather than a crate's default ISO 8601 output.

### 10. The `exe/sq` replacement strategy is underspecified

The plan says `exe/sq` gets "replaced" but doesn't address:
- How does `gem install sift` find the precompiled binary?
- What happens on unsupported platforms (e.g., ARM Linux)?
- The gemspec currently lists `sq` as an executable — removing it changes the gem's behavior
- Should there be a Ruby fallback wrapper that detects the binary?

### 12. `--queue` / `-q` global flag

The parent `QueueCommand` defines `-q`/`--queue PATH` as a global flag available to all subcommands. Clap handles this differently than OptionParser — the flag must be on the top-level `Cli` struct and propagated. The plan's struct shows this correctly but it's worth noting explicitly.

---

## Magnus vs. Strong Contract

**Recommendation: Drop Magnus. Define the JSONL schema as the contract.**

The JSONL queue is already a clean boundary between `sq` (Rust) and `sift` (Ruby TUI):
- Both tools read/write the same file
- File locking (flock) handles concurrency
- The Item schema is simple and stable
- No shared memory, no FFI, no process communication

Magnus would only make sense if the Ruby TUI needed Rust queue operations **in-process** for performance (e.g., filtering 10k+ items without jq). But if `sift` continues to work fine with its own `Queue` class reading the same JSONL, then **the file format IS the contract** and Magnus adds coupling for no gain.

A strong contract means:
1. **Document the JSONL schema explicitly** — field names, types, omission rules, timestamp format
2. **Add cross-language parity tests** — Ruby writes → Rust reads, and vice versa
3. **Version the schema** if it ever changes

Replace Phase 2 (Magnus) with a "Schema Contract" section that formalizes the JSONL format as the integration point.

---

## Suggestions

### A. Add a parity test harness early

Set up a test harness in week 1 that:
1. Runs a Ruby `sq` command against a fixture queue
2. Runs the equivalent Rust `sq` command against the same queue
3. Diffs stdout, stderr, and the resulting JSONL

This catches format drift immediately and provides confidence throughout development.

### B. Consider `--help` output parity

Users switching from Ruby to Rust `sq` will notice if `--help` output changes significantly. Clap's default help style differs substantially from OptionParser's.

### D. Consider the `--system-prompt` flag scope

If `--system-prompt` exists on `sq add`, verify the actual implementation before starting.

### E. The `formatters.rs` file needs significant detail

The text output format (non-JSON) uses `cli-ui` colored frames when available, with a plain fallback. The Rust version needs to decide: always plain? Use a Rust coloring crate? This affects the parity goal for text output.

---

## What the plan gets right

- Using external `jq` for Phase 1 filtering avoids a huge scope increase
- File-based JSONL queue means zero coordination needed between Ruby TUI and Rust CLI
- The dependency list is reasonable and well-chosen (minus `serde_yaml`, which can be dropped)
- Risk mitigation table is practical

---

## Verdict

**Approve with revisions.** The plan is solid architecturally. Key changes needed:

1. **Fix `sq edit` flag spec** (issue #2) — this is the most impactful gap
2. **Add a `prime` design section** using clap runtime introspection (issue #4)
3. **Add serde serialization rules** for field omission (issue #7)
4. **Replace Phase 2 (Magnus) with a schema contract** — document the JSONL format as the integration boundary
5. **Drop `serde_yaml`** and `config.rs` complexity — three lines of queue path resolution replaces it
