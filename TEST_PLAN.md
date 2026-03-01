# High-Impact Testing Implementation Plan

## Context

The sift codebase has significant test coverage for queue operations, CLI commands, and config management, but critical modules like `Client.rb` (real Claude API wrapper) and `Git.rb` (git command executor) lack unit tests. Additionally, integration tests and edge cases in session handling are missing. These gaps leave core functionality—agent execution and git operations—untested for error conditions, edge cases, and contract violations.

**Problem**: Without these tests:
- Silent failures in Client when Claude API changes or network fails
- Undetected git command failures (missing commands, permission errors, branch conflicts)
- Session resumption bugs go unnoticed
- Integration failures between components aren't caught
- Error message quality issues

**Goal**: Implement comprehensive tests for Client, Git, and integration scenarios, enabling confidence in error handling, session management, and cross-component interactions.

---

## Design Decisions Confirmed

1. **Client.rb testing scope**: ✓ Verify exact CLI command construction
   - Assert `--model opus`, `--mode acceptEdits`, flags appear in exact args
   - Catches flag order and formatting bugs

2. **Git error handling**: ✓ Test current behavior as-is
   - Some methods return false on error (`branch_exists?`, `worktree_valid?`)
   - Others raise (`add_worktree`, `diff`)
   - Test each method's current contract without refactoring

3. **Integration test scope**: ✓ Use real Queue file I/O
   - Create temp queue.jsonl files
   - Verify full persistence + async flow end-to-end
   - Tests verify queue state transitions, not mocked behavior

4. **Session edge cases**: ✓ Add session not found tests
   - Test fallback scan when session not in primary path
   - Test error handling when session file missing
   - Test malformed session IDs

---

## Implementation Details

### Phase 1: Client.rb Unit Tests
**File**: Create `test/sift/client_test.rb`

#### Test Coverage (19 test cases)
1. Successful prompt execution
2. Session resumption with --resume flag
3. Append system prompt functionality
4. Working directory context passed to CLI
5. Error: Command not found (Errno::ENOENT)
6. Error: Non-zero exit status
7. Error: Invalid JSON response
8. Error: System call failure
9. Analyze diff convenience method
10. Model flag construction
11. Permission mode flag construction
12. Config flags merged correctly
13. Multiple flags in correct order
14. Empty flags array handled
15. Session ID from response captured
16. Stderr captured on error
17. Zero-length response handling
18. Large response handling
19. Timeout behavior

### Phase 2: Git.rb Unit Tests
**File**: Create `test/sift/git_test.rb`

#### Test Coverage (19 test cases)
1. branch_exists? returns true
2. branch_exists? returns false
3. add_worktree success
4. add_worktree failure with stderr
5. worktree_valid? returns true
6. worktree_valid? returns false
7. enable_worktree_config success
8. enable_worktree_config idempotent
9. set_worktree_config with spaces in value
10. set_worktree_config with special chars
11. info_exclude_path success
12. info_exclude_path failure
13. has_commits_beyond? returns true
14. has_commits_beyond? returns false (zero commits)
15. has_commits_beyond? error handling
16. diff success with unified output
17. diff failure
18. worktree_dirty? returns true
19. worktree_dirty? returns false
20. worktree_diff success
21. worktree_diff failure

### Phase 3: Integration Tests
**File**: Create `test/sift/integration_test.rb`

#### Test Coverage (6 scenarios)
1. Add item → spawn agent → agent completes → transcript appended
2. Blocked item dependencies resolved correctly
3. Worktree creation and diff generation
4. Agent resumption across sessions with session ID persistence
5. Error recovery: agent fails, item stays pending, retry possible
6. General agent result becomes new queue item

### Phase 4: SessionTranscript Edge Cases
**File**: Extend `test/sift/session_transcript_test.rb`

#### Additional Test Coverage (8 cases)
1. Corrupt JSONL lines skipped gracefully
2. Missing assistant message ID handling
3. Tool result without matching tool call
4. Very long tool output truncation
5. Unusual tool names fallback
6. Empty session file handling
7. Session with only tool results (no user/assistant)
8. Plan paths extracted from Write tool and file-history-snapshot

### Phase 5: Error Handling & Edge Cases
**File**: Create `test/sift/error_handling_test.rb`

#### Test Coverage (6 scenarios)
1. Queue corruption recovery
2. File locking contention
3. Config missing required fields
4. Git command with special characters in branch name
5. Worktree cleanup on failed creation
6. Session resume with missing session file

---

## Mock Strategy

**No external mocking libraries** (per project rules). Use Ruby singleton methods to mock `Open3.capture3`:

```ruby
def mock_open3(response:, session_id:, exit_status: 0)
  @original_open3 = Open3.method(:capture3)
  Open3.define_singleton_method(:capture3) do |*args|
    ["#{response}", "", Process::Status.new(exit_status)]
  end
end
```

Create `test/support/mock_helpers.rb` with:
- `MockCommand` class to capture and validate command args
- `mock_client_response` helper for Client tests
- `mock_git_output` helper for Git tests
- `capture_open3_calls` assertion helper

---

## Critical Files to Create/Modify

| File | Purpose | Type |
|------|---------|------|
| `test/sift/client_test.rb` | Unit tests for Client | New |
| `test/sift/git_test.rb` | Unit tests for Git | New |
| `test/sift/integration_test.rb` | Cross-component tests | New |
| `test/support/mock_helpers.rb` | Mock/helper utilities | New |
| `test/sift/session_transcript_test.rb` | Extend with edge cases | Modify |
| `test/sift/error_handling_test.rb` | Error scenario tests | New |
| `TEST_PLAN.md` | This planning document | New |

---

## Verification Strategy

```bash
# Run all tests
bundle exec rake test

# Run specific test suite
bundle exec rake test TEST=test/sift/client_test.rb
```

Verify:
- All new tests pass
- No existing tests broken
- Code coverage increased for Client, Git, integration scenarios

Manual spot checks:
1. `sift --dry` works (DryClient still functions)
2. `sift` launches TUI normally
3. `sq add --text "test"` creates item
4. `sq list` shows items
