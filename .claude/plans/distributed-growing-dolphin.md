# Review: Rust `sq` CLI Rewrite Plan

## Overall Assessment

The plan is **well-structured and thorough** — it correctly identifies the distribution friction problem, proposes a reasonable phased approach, and demonstrates solid understanding of the existing Ruby implementation. However, there are several issues ranging from inaccuracies to missing concerns that should be addressed before implementation.

---

## Issues

### 1. `transcript` source type is missing from the plan

The plan lists valid source types as `"diff", "file", "text", "directory"` (matching `VALID_SOURCE_TYPES` in `queue.rb`), but `sq edit --add-transcript PATH` accepts a `"transcript"` type source. The Rust `Source` struct and its deserialization must handle `transcript` as a valid type, even if `sq add` doesn't create them directly. Items read from disk may contain transcript sources appended by the TUI agent runner.

**Impact:** Rust CLI would fail to parse existing queue files containing transcript sources.

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

The plan says `--filter 'select(...)'` pipes items to jq. The actual Ruby wraps it as:
```ruby
jq_filter(items, "[.[] | #{options[:filter]}]")
```
And sorting uses:
```ruby
jq_filter(items, "sort_by(#{path} // infinite)")
```
Note the `// infinite` fallback for null sort keys. The `-e` flag is also passed to jq. These details matter for byte-for-byte parity.

### 4. `prime` is harder to port than implied

`sq prime` dynamically introspects all registered subcommands via Ruby's `OptionParser` to generate flag documentation. In Rust with clap, you'd need to either:
- Hardcode the help text (diverges over time)
- Use clap's introspection to extract flag metadata programmatically
- Generate it at build time

This is non-trivial and deserves its own design section. The plan treats it as just another subcommand.

### 5. `--system-prompt` flag is mentioned in CLAUDE.md but not in the plan

The CLAUDE.md examples show `sq add --system-prompt prompts/sec.md`. If this flag exists in the actual `add` implementation, the Rust version needs it too. (Worth verifying — it may only be documented aspirationally.)

### 6. JSON output format: `pretty_generate` vs compact

`sq list --json` uses `JSON.pretty_generate` (indented), while JSONL on disk is compact (one line per item). `sq show --json` also uses `pretty_generate`. The plan says "byte-for-byte JSON output parity" but doesn't call out this distinction. Rust's `serde_json` defaults to compact — you'd need `serde_json::to_string_pretty` for the CLI output paths.

### 7. `to_h` field omission rules need exact replication

The Ruby `Item#to_h` uses `.compact` and conditional inclusion:
- `title` omitted when nil
- `worktree` omitted when nil
- `blocked_by` omitted when empty
- `errors` omitted when empty
- `session_id` is always included (even when nil — it's not compacted the same way)

Getting serde to replicate this requires careful use of `#[serde(skip_serializing_if = "...")]` with different predicates per field. The plan's Rust struct definition doesn't address this.

### 8. Timestamp format precision

The plan says "ISO8601 with .000Z precision". Ruby uses `Time.now.utc.iso8601(3)` which produces `2025-03-01T12:34:56.789Z`. The Rust `time` crate's default ISO8601 formatting differs — you'll need a custom format string. This is a common source of parity bugs.

### 9. `claim` semantics may not be needed in Phase 1

The plan lists `claim(id)` as a required queue method. However, `claim` is only used by the Ruby TUI (`sift`), not by any `sq` subcommand. Since Phase 1 only replaces `sq`, implementing `claim` adds complexity for no immediate value. Consider deferring it.

### 10. The `exe/sq` replacement strategy is underspecified

The plan says `exe/sq` gets "replaced" but doesn't address:
- How does `gem install sift` find the precompiled binary?
- What happens on unsupported platforms (e.g., ARM Linux)?
- The gemspec currently lists `sq` as an executable — removing it changes the gem's behavior
- Should there be a Ruby fallback wrapper that detects the binary?

### 11. Config loading needs more detail

The Rust CLI needs to load `.sift/config.yml` and `~/.config/sift/config.yml` and respect `SIFT_QUEUE_PATH`. The plan mentions `config.rs` but doesn't discuss YAML parsing (needs a dep like `serde_yaml`), the merge precedence, or the specific config keys the CLI actually uses (primarily just `queue_path`).

### 12. `--queue` / `-q` global flag

The parent `QueueCommand` defines `-q`/`--queue PATH` as a global flag available to all subcommands. The plan's clap struct shows this correctly on the top-level `Cli`, but it's worth noting this flag must be propagated to all subcommands — clap handles this differently than OptionParser.

---

## Suggestions

### A. Add a parity test harness early

Rather than building all commands then testing parity, set up a test harness in week 1 that:
1. Runs a Ruby `sq` command against a fixture queue
2. Runs the equivalent Rust `sq` command against the same queue
3. Diffs stdout, stderr, and the resulting JSONL

This catches format drift immediately and provides confidence throughout development.

### B. Consider `--help` output parity

Users switching from Ruby to Rust `sq` will notice if `--help` output changes significantly. The plan doesn't mention help text formatting at all. Clap's default help style differs substantially from OptionParser's.

### C. Missing dependency: `serde_yaml`

The config system requires YAML parsing. Add to dependencies:
```toml
serde_yaml = "0.9"
```

### D. Consider the `--system-prompt` flag scope

If `--system-prompt` exists on `sq add`, it means sources may include a `system_prompt` field or items have a `system_prompt` attribute. Verify the actual implementation before starting.

### E. The `formatters.rs` file needs significant detail

The text output format (non-JSON) uses `cli-ui` colored frames when available, with a plain fallback. The Rust version needs to decide: always plain? Use a Rust coloring crate? This affects the "byte-for-byte parity" goal for text output.

---

## What the plan gets right

- Correct phasing: Phase 1 (pure Rust CLI) before Phase 2 (Magnus FFI) is the right call
- Using external `jq` for Phase 1 filtering avoids a huge scope increase
- File-based JSONL queue means zero coordination needed between Ruby TUI and Rust CLI
- The dependency list is reasonable and well-chosen
- Risk mitigation table is practical
- The decision to skip Magnus unless benchmarks justify it shows good restraint

---

## Verdict

**Approve with revisions.** The plan is solid architecturally but needs corrections to the command flag specifications (especially `edit` and source types) and more detail on serialization parity, config loading, and the `prime` command. Address the issues above before starting implementation — most are specification gaps that would become bugs if discovered mid-build.
