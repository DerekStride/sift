# Implementation Plan: Rewrite `sq` in Rust with Magnus Exploration

## Context

**Problem**: `sq` distribution friction. Users must install Ruby 3.1+ and use Bundler to run the queue CLI. This creates barriers for adoption and integration into non-Ruby workflows.

**Solution**: Rewrite `sq` as a compiled Rust binary, achieving single-file distribution and eliminating Ruby runtime dependency. After Phase 1 proves successful, optionally explore Magnus for shared queue model between Rust CLI and Ruby TUI.

**User Constraints**:
- Timeline: High priority (1-2 weeks) — distribution friction is real and blocking
- Testing: Strict parity — all Ruby `sq` behavior must replicate exactly
- Platforms: Linux x86_64 (must-have), macOS (should-have)
- Transition: Immediate replacement (no parallel maintenance window)
- Filtering: Keep external `jq` binary for Phase 1 (lower risk)
- Magnus: Explore in Phase 2 only, after Phase 1 validates approach

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
│   │   └── config.rs                   # Load .sift/config.yml or defaults
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
Must achieve exact parity with Ruby's `Sift::Queue`:
- `push(sources, title, metadata, session_id, blocked_by) → Item`
- `all() → Vec<Item>`
- `find(id) → Option<Item>`
- `update(id, attrs) → Item`
- `remove(id) → Item`
- `claim(id) → Item` (atomic pending→in_progress transition)
- JSONL I/O with `flock(LOCK_EX)` for writes, `flock(LOCK_SH)` for reads
- Corrupt line skipping (warn, don't fail) like Ruby
- ID generation: 3-char alphanumeric, no collisions

**Key types**:
```rust
pub struct Item {
    pub id: String,
    pub title: Option<String>,
    pub status: Status,
    pub sources: Vec<Source>,
    pub metadata: serde_json::Value,
    pub session_id: Option<String>,
    pub worktree: Option<Worktree>,
    pub blocked_by: Vec<String>,
    pub errors: Vec<String>,
    pub created_at: String,  // ISO8601 with .000Z precision
    pub updated_at: String,
}

#[derive(Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Status { Pending, InProgress, Closed }

pub struct Source {
    pub type_: String,  // "diff", "file", "text", "directory"
    pub path: Option<String>,
    pub content: Option<String>,
    pub session_id: Option<String>,
}
```

**2. `sq-rust/src/cli/commands/list.rs` — Filtering & Sorting**
Must replicate `sq list` flags exactly:
- `--status pending|in_progress|closed` → filter by status
- `--filter 'select(...)'` → pipe items JSON to `jq` for filtering, parse result
- `--sort .created_at` → pipe items JSON to `jq 'sort_by(.created_at)'`
- `--reverse` → sort descending
- `--ready` → show pending + unblocked items
- `--json` → output JSONL
- Default: human-readable table via formatters

**Key pattern**: For Phase 1, call external `jq` via `std::process::Command` to eliminate parsing complexity. Test that Rust input and Ruby input produce identical jq output.

**3. `sq-rust/src/cli/commands/add.rs` — Item Creation**
Flags: `--text TEXT`, `--diff PATH`, `--file PATH`, `--directory PATH`, `--stdin TYPE`, `--title TITLE`, `--metadata JSON`, `--blocked-by IDS`
- Validate at least one source exists
- Return item ID to stdout (like Ruby)
- Generate 3-char ID, check no collision
- Set created_at/updated_at to `Time::now().utc().iso8601(3)`

**4. `sq-rust/src/main.rs` — Entry Point**
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

### Key Dependencies

```toml
[dependencies]
clap = { version = "4.5", features = ["derive"] }
serde = { version = "1.0", features = ["derive"] }
serde_json = "1.0"
time = { version = "0.3", features = ["formatting", "parsing"] }
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

## Phase 2: Magnus Exploration (Weeks 3-4, Conditional)

Only pursue if Phase 1 succeeds AND:
- Ruby TUI (`sift`) needs performance improvements for filtering/sorting large queues
- Maintainability benefit (shared model) outweighs integration complexity

**Approach**: Create `sq-magnus/` crate exposing Rust types to Ruby via FFI. Ruby can `require "sq_magnus"` and use Rust queue operations.

**Decision point (end of Phase 1)**: Benchmark filtering 10k queue items. If Rust is 10x+ faster, pursue Magnus. Otherwise, stop at Phase 1.

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
   sq add --text "test item"
   sq list
   sq list --filter 'select(.status == "pending")'
   sq show <id>
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
