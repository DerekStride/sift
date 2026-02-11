# Agent Instructions

## Project Overview

**Sift** is a queue-driven review system where humans make decisions and agents do the work. It inverts the typical agent CLI pattern: instead of agents driving with human oversight, humans drive decisions while agents provide analysis and execute tasks.

## Key Concepts

- **Queue**: JSONL-based work items (review, analysis, revision)
- **Review Loop**: TUI for human decisions (approve/reject/revise)
- **Sticky Sessions**: Agent conversations persist per item for revisions
- **Roast Integration**: Can orchestrate Roast workflows or use custom cogs

## Project Structure

```
lib/sift/
├── cli.rb                # CLI module
├── cli/
│   ├── base.rb           # Base command class (OptionParser, subcommand routing)
│   ├── help_renderer.rb  # gh-style help output
│   ├── queue_command.rb  # `sq` root command
│   └── queue/            # One class per subcommand
│       ├── add.rb
│       ├── edit.rb
│       ├── list.rb
│       ├── show.rb
│       ├── rm.rb
│       └── formatters.rb # Shared output helpers
├── review_loop.rb        # Main TUI flow
├── queue.rb              # JSONL queue management
├── client.rb             # Claude API wrapper
├── diff_parser.rb        # Git diff parsing
├── git_actions.rb        # Stage/revert operations
└── roast/                # Roast integration layer
```

## Design Documents

- `doc/specs/EXPLORATION.md` - Original design exploration and decisions

## Running Tests

```bash
bundle exec rake test
```

## CLI Entry Points

Two executables in `exe/`:

- **`sift`** — Interactive review loop TUI. Reads queue items, presents them for human review.
- **`sq`** — Queue management CLI. Add, list, show, edit, and remove queue items.

### `sq` Subcommands

```bash
sq add --text "Review this"          # Add item with text source
sq add --diff changes.patch          # Add item with diff source
sq list --status pending             # List/filter items
sq show <id> --json                  # Show item details
sq edit <id> --set-status approved   # Modify item
sq rm <id>                           # Remove item
```

Run `sq --help` or `sq <command> --help` for full flag details.

### Adding a New Subcommand

Each subcommand is a `Sift::CLI::Base` subclass. The pattern:

```ruby
class Sift::CLI::Queue::MyCommand < Sift::CLI::Base
  command_name "mycommand"
  summary "One-line description"

  def define_flags(parser, options)
    parser.on("--flag VALUE", "Description") { |v| options[:flag] = v }
    super  # chains inherited flags from parent
  end

  def execute
    # Do work, return exit code (0 = success, 1 = error)
    0
  end
end
```

Register it in `lib/sift/cli/queue_command.rb`:
```ruby
register_subcommand Queue::MyCommand, category: :core
```

## Key Patterns

### Review Loop Flow

1. Load diff hunks
2. Display hunk (no Claude call yet)
3. Human decides: `a`ccept / `r`eject / `?` ask Claude
4. If `?`: Claude analyzes, show result, prompt again
5. Accept → stage hunk, Reject → revert hunk

### Roast Integration

1. **Wrapper**: Sift calls `Roast::Workflow.from_file` externally
2. **Custom Cog**: Roast workflows use `sift_output` cog to push results

## Issue Tracking

This project uses **bd** (beads) for issue tracking.

```bash
bd ready              # Find available work
bd show <id>          # View issue details
bd update <id> -s in_progress  # Claim work
bd close <id> -r "reason"      # Complete work
bd dep add <id> <blocker>      # Add dependency
```

