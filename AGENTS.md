# Agent Instructions

## Project Overview

**Sift** is a queue-driven review system where humans make decisions and agents do the work.

This repository owns the **Sift TUI and agent workflow**. The `sq` queue CLI now lives in its own repository and is treated as an external dependency.

## Key Concepts

- **Queue**: JSONL-based work items consumed by the review loop
- **Review Loop**: TUI where humans view items, spawn agents, close items, or ask general questions
- **Background Agents**: Run as Async fibers with semaphore-limited concurrency
- **Sticky Sessions**: Agent conversations persist per item via Claude session IDs
- **General Agents**: Free-form agents not tied to items — results become new queue items
- **System Prompts**: Customizable per-session or per-item agent behavior

## Project Structure

```text
lib/sift/
├── cli.rb
├── cli/
│   ├── base.rb
│   ├── help_renderer.rb
│   ├── init.rb
│   └── sift_command.rb
├── queue.rb
├── client.rb
├── agent_runner.rb
├── worktree.rb
├── editor.rb
├── prime.rb
└── tui/
    ├── app.rb
    ├── card.rb
    ├── exec_command.rb
    ├── keymap.rb
    ├── messages.rb
    └── styles.rb
```

Other supporting modules live alongside these in `lib/sift/`.

## Running Tests

```bash
bundle exec rake test
```

## Testing Rules

- **No real git commands in tests.** Never call `system("git ...")` or execute git via `Open3` in test code. Use `FakeGit` (defined in `test/support/fake_git.rb`) for all git interactions.
- **Isolate config from the environment.** Tests must not depend on `.sift/config.yml` or `~/.config/sift/config.yml`. Use `Config.load(project_path: "/nonexistent", user_path: "/nonexistent")` for defaults-only config, or stub `Config.load`.

## CLI Entry Points

- **`sift`** — Interactive review loop TUI. Run `sift --help` to see all options.
- **`sq`** — External queue CLI used alongside Sift. It is no longer implemented in this repository.

## Integration with `sq`

Sift shells out to `sq prime` to preload queue workflow context for agents.

Common queue operations are expected to happen through `sq`, for example:

```bash
sq add --text "Review this"
sq list --status pending
sq show <id>
sq edit <id> --set-status closed
```

When updating docs or UX around queue management, keep the boundary clear:

- `sq` owns queue management UX
- `sift` owns review-loop UX

## Review Loop Flow

1. Load pending items from the queue
2. Display the current item card
3. Human chooses action: `v`iew / `a`gent / `c`lose / `g`eneral / `n`ext / `p`rev / `q`uit
4. If `a`gent: prompt for instruction → spawn background agent → continue reviewing
5. If `g`eneral: prompt for instruction → spawn free-form agent → result becomes a new queue item
6. If `c`lose: mark the item closed and advance
7. When agents finish: transcript appended as source, session ID stored for continuity
8. Loop exits when no pending items remain and no agents are running

## Agent Session Continuity

- First agent turn: all item sources are included in the prompt
- Subsequent turns: only the user prompt is sent (`claude --resume` handles context)
- Session ID is stored on the queue item for future turns

## Async Concurrency

- `AgentRunner` manages background fibers gated by `Async::Semaphore`
- `App` polls for completed agents between user actions
- Non-blocking input keeps the TUI responsive while agents run
- `Log.quiet { ... }` buffers logs during input to avoid stderr corruption

## File Locking

- Queue uses `flock(LOCK_EX)` for writes and `flock(LOCK_SH)` for reads
- `claim(id)` atomically transitions `pending -> in_progress`
- Corrupt JSONL lines are skipped with a warning rather than treated as fatal

## Agent Docs

The `agent-docs/` directory contains detailed documentation on specific subsystems. Consult these when working in the relevant area.

## Issue Tracking

This project uses **sq** for issue tracking.

```bash
sq -q .sift/issues.jsonl ready
sq -q .sift/issues.jsonl show <id>
sq -q .sift/issues.jsonl edit <id> --set-blocked-by <ids>
```
