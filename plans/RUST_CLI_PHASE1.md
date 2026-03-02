# Implementation Plan: Rewrite `sq` in Rust

## Context

**Problem**: `sq` distribution friction. Users must install Ruby 3.1+ and use Bundler to run the queue CLI. This creates barriers for adoption and integration into non-Ruby workflows.

**Solution**: Rewrite `sq` as a compiled Rust binary, achieving single-file distribution and eliminating Ruby runtime dependency. The JSONL queue file format serves as the integration contract between the Rust CLI and the Ruby TUI.

**User Constraints**:
- Timeline: High priority (1-2 weeks) — distribution friction is real and blocking
- Testing: Strict parity — all Ruby `sq` behavior must replicate exactly
- Platforms: Linux x86_64 (must-have), macOS (should-have)
- Transition: Immediate replacement (no parallel maintenance window)
- Filtering: Keep external `jq` binary for Phase 1 (lower risk)

---

## Phase 1: Rust CLI Foundation (Weeks 1-2)

### Goals
- Implement all 6 `sq` subcommands in Rust (`add`, `list`, `show`, `edit`, `rm`, `prime`)
- Achieve byte-for-byte JSON output parity with Ruby
- Support Linux x86_64 and macOS
- Distribute as single compiled binary

### Project Structure

```
/home/user/sift/
├── Cargo.toml                          # Workspace root
├── sq-rust/                            # NEW: Rust CLI
│   ├── Cargo.toml
│   ├── src/
│   │   ├── main.rs                     # CLI entry point, clap subcommand routing
│   │   ├── lib.rs                      # Exports queue and cli modules
│   │   ├── queue/
│   │   │   ├── mod.rs                  # Queue struct, JSONL I/O, mutations
│   │   ├── cli/
│   │   │   ├── mod.rs                  # Command trait, subcommand enum
│   │   │   ├── commands/
│   │   │   │   ├── add.rs              # `sq add` implementation
│   │   │   │   ├── list.rs             # `sq list` with --filter/--sort via jq
│   │   │   │   ├── show.rs             # `sq show` item details
│   │   │   │   ├── edit.rs             # `sq edit` mutations
│   │   │   │   ├── rm.rs               # `sq rm` deletion
│   │   │   │   └── prime.rs            # `sq prime` docs generator
│   │   │   └── formatters.rs           # print_item_summary, JSON output
│   │   └── queue_path.rs               # --queue flag > SIFT_QUEUE_PATH env > default
│   ├── tests/
│   │   ├── queue_parity.rs             # JSONL round-trip tests vs Ruby
│   │   ├── cli_integration.rs          # Test each subcommand with temp queue
│   │   └── fixtures/
│   │       └── queue_samples.jsonl     # Test data from Ruby queue
│   └── Makefile                        # Build targets for Linux/macOS
├── lib/sift/queue.rb                   # UNCHANGED
├── lib/sift/cli/queue/                 # UNCHANGED during Phase 1
├── exe/sq                              # REPLACED: calls compiled Rust binary
├── Rakefile                            # Updated to build sq-rust
└── sift.gemspec                        # Add sq-rust build step
```

### Critical Implementation Files

**1. `sq-rust/src/queue/mod.rs` — Core Queue Logic**
Must achieve exact parity with Ruby's `Sift::Queue` (methods used by `sq` subcommands only):
- `push(sources, title, metadata, session_id, blocked_by) → Item`
- `all() → Vec<Item>`
- `find(id) → Option<Item>`
- `update(id, attrs) → Item`
- `remove(id) → Item`
- `filter(status) → Vec<Item>`
- `ready() → Vec<Item>` (pending + unblocked)
- JSONL I/O with `flock(LOCK_EX)` for writes, `flock(LOCK_SH)` for reads
- Corrupt line skipping (warn, don't fail) like Ruby
- ID generation: 3-char alphanumeric (a-z0-9), no collisions

Note: `claim(id)` is deferred — it's only used by `AgentRunner#spawn` in the Ruby TUI, not by any `sq` subcommand. It implements a lease pattern (acquire under LOCK_EX → hold during agent execution → auto-release via ensure). Nothing in the JSONL format is claim-specific; it's purely behavioral. See Schema Contract section for flock invariants.

**Key types**:
```rust
pub struct Item {
    pub id: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub title: Option<String>,
    pub status: Status,
    pub sources: Vec<Source>,
    pub metadata: serde_json::Value,
    pub session_id: Option<String>,  // Always serialized, even when null
    #[serde(skip_serializing_if = "Option::is_none")]
    pub worktree: Option<Worktree>,
    #[serde(skip_serializing_if = "Vec::is_empty", default)]
    pub blocked_by: Vec<String>,
    #[serde(skip_serializing_if = "Vec::is_empty", default)]
    pub errors: Vec<String>,
    pub created_at: String,  // ISO8601 with .000Z precision
    pub updated_at: String,
}

#[derive(Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Status { Pending, InProgress, Closed }

pub struct Source {
    #[serde(rename = "type")]
    pub type_: String,  // "diff", "file", "text", "directory", "transcript", etc.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub path: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub content: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub session_id: Option<String>,
}
```

**Serialization rules** (must match Ruby `Item#to_h` exactly):
- `title`: omitted when `None`
- `worktree`: omitted when `None`
- `blocked_by`: omitted when empty vec
- `errors`: omitted when empty vec
- `session_id`: **always included**, even when `null` (not compacted like other Optional fields)
- `metadata`: always included (empty `{}` when no metadata)
- Source `type_`: string field, not a restricted enum — must round-trip unknown types (e.g., `"transcript"`) without error

**2. `sq-rust/src/cli/commands/list.rs` — Filtering & Sorting**
Must replicate `sq list` flags exactly:
- `--status pending|in_progress|closed` → filter by status
- `--filter 'select(...)'` → wrap as `[.[] | <expr>]` and pipe to `jq -e`
- `--sort .created_at` → wrap as `sort_by(<path> // infinite)` and pipe to `jq -e`
- `--reverse` → reverse result array after sorting
- `--ready` → show pending + unblocked items
- `--json` → output with `serde_json::to_string_pretty` (indented, not compact)
- Default: human-readable table via formatters

**Key pattern**: For Phase 1, call external `jq` via `std::process::Command` to eliminate parsing complexity. The exact jq invocation is:
```rust
// Filtering: jq -e '[.[] | select(.status == "pending")]'
// Sorting:   jq -e 'sort_by(.metadata.priority // infinite)'
// Input:     JSON.generate(items.map(&:to_h)) piped to stdin
// Output:    parsed back into Vec<Item>
```
Note the `// infinite` fallback for null sort keys and the `-e` flag (exit non-zero on `false`/`null`).

**3. `sq-rust/src/cli/commands/add.rs` — Item Creation**
Flags: `--text TEXT`, `--diff PATH`, `--file PATH`, `--directory PATH`, `--stdin TYPE`, `--title TITLE`, `--metadata JSON`, `--blocked-by IDS`
- Validate at least one source exists
- Return item ID to stdout (like Ruby)
- Generate 3-char ID (a-z0-9), check no collision
- Set created_at/updated_at using explicit format: `%Y-%m-%dT%H:%M:%S%.3fZ` (must match Ruby's `Time.now.utc.iso8601(3)`)

**4. `sq-rust/src/cli/commands/edit.rs` — Item Mutations**
Full flag set (must match Ruby exactly):
- `--set-status STATUS` — Change status (pending|in_progress|closed)
- `--set-title TITLE` — Set title
- `--set-metadata JSON` — Replace metadata (parsed as JSON, error on invalid)
- `--set-blocked-by IDS` — Set blocker IDs (comma-separated, empty string clears)
- `--add-diff PATH` — Add diff source (repeatable)
- `--add-file PATH` — Add file source (repeatable)
- `--add-text STRING` — Add text source (repeatable)
- `--add-directory PATH` — Add directory source (repeatable)
- `--add-transcript PATH` — Add transcript source (repeatable)
- `--rm-source INDEX` — Remove source by 0-based index (repeatable)

**Critical behavior**: `--rm-source` indices must be sorted in reverse before deletion to preserve correctness. Cannot remove all sources (error). At least one change flag required (error if none). Returns updated item ID to stdout.

**5. `sq-rust/src/main.rs` — Entry Point**
Use `clap` 4.x derive macros for subcommand routing:
```rust
#[derive(Parser)]
#[command(name = "sq")]
struct Cli {
    #[arg(short, long)]
    queue: Option<PathBuf>,

    #[command(subcommand)]
    command: Commands,
}

#[derive(Subcommand)]
enum Commands {
    Add(AddArgs),
    List(ListArgs),
    Show(ShowArgs),
    Edit(EditArgs),
    Rm(RmArgs),
    Prime,
}
```

**6. `sq-rust/src/cli/commands/prime.rs` — Docs Generator via Clap Introspection**

`sq prime` generates markdown documentation about the sift workflow, including an auto-generated command reference with flags for every subcommand. The Ruby implementation uses `OptionParser` introspection. The Rust equivalent uses **clap runtime introspection**.

**Approach**: Build the `Command` object and walk its subcommands at runtime:
```rust
fn generate_command_reference(cmd: &clap::Command) -> String {
    let mut lines = Vec::new();
    for sub in cmd.get_subcommands() {
        if sub.get_name() == "prime" { continue; } // skip self
        lines.push(format!("### `sq {}` — {}\n", sub.get_name(),
            sub.get_about().unwrap_or_default()));
        lines.push("```".to_string());
        for arg in sub.get_arguments() {
            if arg.is_hide_set() || arg.get_id() == "help" || arg.get_id() == "version" { continue; }
            let long = arg.get_long().map(|l| format!("--{}", l));
            let short = arg.get_short().map(|s| format!("-{}", s));
            let names = [short, long].into_iter().flatten().collect::<Vec<_>>().join(", ");
            let value = arg.get_value_names()
                .map(|v| v.iter().map(|s| s.to_string()).collect::<Vec<_>>().join(" "))
                .unwrap_or_default();
            let usage = if value.is_empty() { names } else { format!("{} {}", names, value) };
            let help = arg.get_help().unwrap_or_default();
            lines.push(format!("  {}  {}", usage, help));
        }
        lines.push("```".to_string());
        lines.push(String::new());
    }
    lines.join("\n")
}
```

**Key requirement**: All clap args must set `value_name("PATH")`, `value_name("STATUS")`, etc. to match the Ruby output. Use `#[arg(value_name = "PATH")]` in derive macros.

### Queue Path Resolution

No YAML config loading needed. The `sq` CLI only uses `queue_path`, resolved as:

1. `--queue` / `-q` CLI flag (highest priority)
2. `SIFT_QUEUE_PATH` environment variable
3. `.sift/queue.jsonl` default

```rust
fn resolve_queue_path(cli_flag: Option<&Path>) -> PathBuf {
    cli_flag
        .map(PathBuf::from)
        .or_else(|| std::env::var("SIFT_QUEUE_PATH").ok().map(PathBuf::from))
        .unwrap_or_else(|| PathBuf::from(".sift/queue.jsonl"))
}
```

### Key Dependencies

```toml
[dependencies]
clap = { version = "4.5", features = ["derive"] }
serde = { version = "1.0", features = ["derive"] }
serde_json = "1.0"
chrono = { version = "0.4", features = ["serde"] }  # timestamp formatting
rustix = { version = "0.38", features = ["fs"] }  # flock support
anyhow = "1.0"
thiserror = "1.0"
tempfile = "3.0"  # testing
uuid = { version = "1.0", features = ["v4"] }  # optional, for testing
```

### Testing Strategy (Strict Parity)

**Unit Tests** (`sq-rust/tests/queue_parity.rs`):
- JSONL round-trip tests (Rust parse + serialize must match input)
- Queue mutation tests (add, update, remove operations)
- Concurrent access tests (flock behavior)

**Integration Tests** (`sq-rust/tests/cli_integration.rs`):
- Test each subcommand with temp queue files
- Verify JSON output format matches Ruby exactly
- Test jq filtering and sorting

**Comparison Tests**:
- Generate test data with Ruby, parse with Rust
- Run same operation with both versions
- Compare outputs byte-for-byte

### Build System Integration

**New file: `sq-rust/Cargo.toml`** (workspace member)

**Updated: `/home/user/sift/Cargo.toml`** (workspace root)
```toml
[workspace]
members = ["sq-rust"]
resolver = "2"
```

**Updated: `/home/user/sift/Rakefile`**
```ruby
task default: [:build_sq_rust, :test]

desc "Build Rust sq binary"
task :build_sq_rust do
  unless ENV["SKIP_RUST"]
    sh "cd sq-rust && cargo build --release"
    # Copy binary to exe/sq.rust as backup
    cp "sq-rust/target/release/sq", "exe/sq.rust"
  end
end

desc "Run all tests"
task :test => :build_sq_rust do
  sh "cd sq-rust && cargo test"
  sh "bundle exec minitest test/**/*_test.rb"
end
```

**Updated: `/home/user/sift/sift.gemspec`**
```ruby
spec.files = Dir.glob(%w[lib/**/*.rb exe/* LICENSE.txt README.md sq-rust/src/**/*.rs sq-rust/Cargo.*])

spec.executables = ["sift"]  # Only Ruby entry point
```

### Distribution Strategy

**Phase 1a (Weeks 1-1.5): Development**
- Develop and test Rust binary locally on Linux
- Commit `sq-rust/` directory
- Verify parity tests pass

**Phase 1b (Weeks 1.5-2): Distribution**
- Add build step to Rakefile
- Precompile binaries for Linux x86_64 and macOS (x86_64 + aarch64)
- Host binaries on GitHub Releases or in Sift gem
- `gem install sift` includes precompiled binary, falls back to Ruby `sq` if binary not available

Recommend **precompiled binaries** for 1-2 week timeline.

### Success Criteria (Phase 1)

✅ All 6 subcommands work identically to Ruby version
✅ JSON output byte-for-byte matches Ruby
✅ Test suite runs: `cargo test` (unit + integration) passes 100%
✅ Parity tests confirm Rust and Ruby read/write same JSONL
✅ Linux x86_64 binary compiles and runs
✅ macOS (x86_64 + aarch64) binary compiles
✅ Single binary <20MB (uncompressed)
✅ No Ruby `sq` executable remains in `exe/` (replaced by Rust)

---

## Schema Contract: JSONL Queue Format

The JSONL queue file is the integration boundary between `sq` (Rust) and `sift` (Ruby TUI). Both tools read and write the same file. No FFI, no shared memory, no Magnus needed — the file format IS the contract.

### JSONL Format

Each line is a valid JSON object representing one item. One item per line, no trailing commas.

### Field Specification

| Field | Type | Required | Serialization Rule |
|-------|------|----------|-------------------|
| `id` | string (3-char a-z0-9) | always | always present |
| `status` | `"pending"` \| `"in_progress"` \| `"closed"` | always | always present |
| `sources` | array of Source objects | always | always present (may be empty) |
| `metadata` | object | always | always present (empty `{}` when none) |
| `session_id` | string \| null | always | **always serialized, even when null** |
| `created_at` | string (ISO 8601) | always | format: `YYYY-MM-DDTHH:MM:SS.mmmZ` |
| `updated_at` | string (ISO 8601) | always | format: `YYYY-MM-DDTHH:MM:SS.mmmZ` |
| `title` | string | optional | **omitted when null** (not serialized) |
| `worktree` | object `{path, branch}` | optional | **omitted when null** |
| `blocked_by` | array of strings | optional | **omitted when empty** |
| `errors` | array of objects | optional | **omitted when empty** |

### Source Object

| Field | Type | Required |
|-------|------|----------|
| `type` | string | always (e.g., `"diff"`, `"file"`, `"text"`, `"directory"`, `"transcript"`) |
| `path` | string | omitted when null |
| `content` | string | omitted when null |
| `session_id` | string | omitted when null |

Source `type` is a **free-form string**, not a restricted enum. Unknown types must round-trip without error.

### Concurrency Invariants

- Writers **must** acquire `flock(LOCK_EX)` before modifying the file
- Readers **should** acquire `flock(LOCK_SH)` for consistent reads
- `in_progress` items may revert to `pending` if the holding process crashes (the TUI handles this via `ensure` blocks, not via the file format)
- Corrupt JSONL lines must be skipped with a warning, not treated as fatal errors

### Parity Testing

Cross-language parity tests ensure the contract holds:
1. Ruby writes items → Rust reads and re-serializes → byte-for-byte match
2. Rust writes items → Ruby reads and re-serializes → byte-for-byte match
3. Both produce identical `jq` output for the same filter/sort expressions

---

## Risk Mitigation

| Risk | Mitigation |
|------|-----------|
| 1-2 week deadline is aggressive | Strict scope: 6 subcommands only, no extra features. Use existing test data from Ruby suite. |
| jq dependency not available on user system | Keep fallback: if jq missing, `sq list --filter` fails with helpful error. User can install jq or use `--status` instead. |
| macOS compilation breaks | Test Linux→macOS cross-compilation early (week 1). If too complex, ship Linux binary first, macOS in patch release. |
| JSONL format drift causes breakage | Exhaustive parity tests catch format differences. Test against Ruby-generated queue files daily. |
| Rust binary incompatible with Ruby TUI | Queue is file-based; both tools read/write same JSONL. No compatibility layer needed beyond file format. |

---

## Critical Files to Create

1. **`sq-rust/Cargo.toml`** — Rust package configuration
2. **`sq-rust/src/main.rs`** — Entry point and clap routing
3. **`sq-rust/src/queue/mod.rs`** — Queue JSONL I/O (highest priority)
4. **`sq-rust/src/queue/item.rs`** — Item struct, Status enum, serde implementations
5. **`sq-rust/src/cli/commands/list.rs`** — jq filtering/sorting (second priority)
6. **`sq-rust/src/cli/commands/add.rs`** — Item creation
7. **`sq-rust/src/cli/commands/show.rs`** — Item display
8. **`sq-rust/src/cli/commands/edit.rs`** — Item mutations
9. **`sq-rust/src/cli/commands/rm.rs`** — Item deletion
10. **`sq-rust/src/cli/commands/prime.rs`** — Docs generation
11. **`sq-rust/tests/queue_parity.rs`** — Parity tests vs Ruby
12. **`sq-rust/tests/cli_integration.rs`** — Subcommand tests

## Critical Files to Modify

1. **`/home/user/sift/Cargo.toml`** — Add workspace configuration
2. **`/home/user/sift/Rakefile`** — Add `build_sq_rust` task, update test task
3. **`/home/user/sift/sift.gemspec`** — Include Rust source files, remove sq from executables
4. **`/home/user/sift/exe/sq`** — Replace with symlink/wrapper pointing to compiled binary

---

## Verification (End-to-End Testing)

**After Phase 1 implementation:**
1. Build: `cd sq-rust && cargo build --release`
2. Run parity tests: `cargo test --lib` (all must pass)
3. Run integration tests: `cargo test --test` (all must pass)
4. Manual smoke test:
   ```bash
   sq add --text "test item" --title "Smoke test"
   sq list
   sq list --filter 'select(.status == "pending")'
   sq list --ready
   sq show <id>
   sq show <id> --json
   sq edit <id> --set-title "Updated" --add-text "extra info"
   sq edit <id> --set-status closed
   sq list --status closed
   sq rm <id>
   ```
5. Verify no errors, output format matches Ruby version
6. Cross-platform verification: test macOS binary on actual Mac hardware if available

---

## Timeline Breakdown

**Week 1:**
- Mon-Tue: Queue module (mod.rs, item.rs, locking.rs) with tests
- Wed: CLI entry point and add/rm commands
- Thu: list/show commands, jq integration
- Fri: edit command, integration tests

**Week 2:**
- Mon-Tue: Parity testing, bug fixes
- Wed: Cross-platform build (macOS)
- Thu: Documentation, exe/sq replacement
- Fri: Final testing, release
