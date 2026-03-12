# Sift

Sift is a queue-driven review TUI where humans make decisions and agents do the work.

It sits on top of a JSONL queue and focuses on the interactive review loop: reading items, spawning agents, tracking worktrees, and continuing review while agents run in the background.

## The inversion

Traditional agent CLIs: the agent drives and the human occasionally intervenes.

**Sift inverts this**: the human drives, the queue coordinates, and agents provide signal and execution.

## Relationship to `sq`

Sift now treats `sq` as a separate project.

- `sq` owns queue management and queue-oriented workflows
- `sift` owns the interactive review loop and agent experience

Install `sq` separately:

- Repo: `https://github.com/DerekStride/sq`
- Crate: `cargo install sift-queue`

A typical workflow is:

```bash
sq add --text "Review this change"
sq add --diff changes.patch --file main.rb

sift
```

## Quick start

```bash
bundle install

# Make sure sq is available on PATH
sq --help

# Launch the interactive review TUI
sift

# Or in dry mode (no API calls)
sift --dry
```

## TUI actions

The core workflow in the review TUI:

- **View** (`v`) — open item sources in `$EDITOR`
- **Agent** (`a`) — spawn a background agent for the current item
- **General** (`g`) — spawn a free-form agent not tied to an item
- **Close** (`c`) — mark the item closed and move on

When you press `a` or `g`, type your instruction inline or press `Ctrl+G` to compose in `$EDITOR`.

Run `sift --help` for all available options.

## How agents work

Agents run in the background. While one agent works on an item, you can continue reviewing others.

When an agent finishes, its conversation transcript is appended as a new source on the item. The agent's session ID is stored on the item so future invocations can continue the same conversation.

General agents can also create new queue items for follow-up review.

## Queue model

Sift reads and writes the same queue format used by `sq`.

Common queue actions are expected to happen through `sq`, for example:

```bash
sq list
sq show <id>
sq edit <id> --set-status closed
sq edit <id> --merge-metadata '{"pi_tasks":{"priority":"high"}}'
```

Sift itself focuses on the review loop rather than replacing the queue CLI.

## Development

```bash
bundle exec rake test
```

Set `SIFT_LOG_LEVEL=DEBUG` for verbose logging.
