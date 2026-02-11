# Sift

Queue-driven review system where humans make decisions and agents do the work.

## The Inversion

Traditional agent CLIs: agent drives, human occasionally intervenes.

**Sift inverts this**: human drives decisions, agents provide signal and execute.

```
┌─────────────┐     ┌──────────────┐     ┌─────────────┐
│   Human     │────▶│   Queue      │◀────│   Agents    │
│   (TUI)     │     │   (JSONL)    │     │   (bg)      │
└─────────────┘     └──────────────┘     └─────────────┘
```

## Quick Start

```bash
bundle install

# Review queue items interactively
sift

# Manage the review queue
sq add --text "Review this change"
sq add --diff changes.patch --file main.rb
sq list --status pending
sq show <id>
```

## TUI Hotkeys

| Key | Action |
|-----|--------|
| `a` | Accept (stages hunk) |
| `r` | Reject (reverts hunk) |
| `c` | Add comment |
| `?` | Ask Claude for analysis |
| `v` | Revise analysis with feedback |
| `q` | Quit |

## `sq` — Queue Management CLI

`sq` manages the JSONL review queue. Each subcommand is its own class under `Sift::CLI::Queue::*`.

```bash
sq add --text "Review this"          # Add item with text source
sq add --diff changes.patch          # Add item with diff source
sq add --stdin text < file.txt       # Add item from stdin
sq list                              # List all items
sq list --status pending --json      # Filter + JSON output
sq show <id>                         # Show item details
sq edit <id> --set-status approved   # Update item status
sq rm <id>                           # Remove item
```

Run `sq --help` or `sq <command> --help` for full flag details.

## Architecture

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
├── client.rb             # Claude API wrapper
├── diff_parser.rb        # Git diff → hunks
├── git_actions.rb        # Stage/revert hunks
├── queue.rb              # JSONL queue
├── review_loop.rb        # TUI review flow
└── roast/                # Roast integration
    ├── orchestrator.rb
    └── cogs/
        └── sift_output.rb
```

## Roast Integration

Sift can orchestrate [Roast](https://github.com/Shopify/roast) workflows:

```ruby
# Wrapper approach - Sift calls Roast externally
orchestrator = Sift::Roast::Orchestrator.new
orchestrator.run("analyze.rb", targets: [file])

# Custom cog approach - Roast workflows push to Sift
use [:sift_output], from: "sift/roast/cogs/sift_output"
execute do
  agent(:analyze) { target! }
  sift_output(:result) { agent!(:analyze).response }
end
```

## Development

```bash
bundle exec rake test
```

## Status

Early prototype. See `doc/specs/EXPLORATION.md` for design notes.
