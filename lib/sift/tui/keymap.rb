# frozen_string_literal: true

require_relative "mode"

module Sift
  module TUI
    module Keymap
      KA = Mode::KeyAction

      REVIEWING = Mode.new(:reviewing, [
        KA.new(key: "v",      label: "view",    color: "#56B6C2", category: :action, handler: ->(app) { app.cmd_view }),
        KA.new(key: "a",      label: "agent",   color: "#5B8DEF", category: :action, handler: ->(app) { app.cmd_agent }),
        KA.new(key: "c",      label: "close",   color: "#98C379", category: :action, handler: ->(app) { app.cmd_close }),
        KA.new(key: "g",      label: "general", color: "#C678DD", category: :action, handler: ->(app) { app.cmd_general }),
        KA.new(key: "n",      label: "next",    color: "#E5C07B", category: :nav,    handler: ->(app) { app.cmd_next }),
        KA.new(key: "p",      label: "prev",    color: "#E5C07B", category: :nav,    handler: ->(app) { app.cmd_prev }),
        KA.new(key: "q",      label: "quit",    color: "#666666", category: :quit,   handler: ->(app) { app.cmd_quit }),
        KA.new(key: "ctrl+c", label: nil,       color: nil,       category: :hidden, handler: ->(app) { app.cmd_quit }),
      ])

      PROMPTING = Mode.new(:prompting, [
        KA.new(key: "enter",  label: nil, color: nil, category: :hidden, handler: ->(app) { app.cmd_submit_prompt }),
        KA.new(key: "ctrl+g", label: nil, color: nil, category: :hidden, handler: ->(app) { app.cmd_submit_via_editor }),
        KA.new(key: "esc",    label: nil, color: nil, category: :hidden, handler: ->(app) { app.cmd_cancel_prompt }),
        KA.new(key: "ctrl+c", label: nil, color: nil, category: :hidden, handler: ->(app) { app.cmd_cancel_prompt }),
      ])

      WAITING = Mode.new(:waiting, [
        KA.new(key: "g",      label: "general", color: "#C678DD", category: :action, handler: ->(app) { app.cmd_general }),
        KA.new(key: "q",      label: "quit",    color: "#666666", category: :quit,   handler: ->(app) { app.cmd_quit }),
        KA.new(key: "ctrl+c", label: nil,       color: nil,       category: :hidden, handler: ->(app) { app.cmd_quit }),
      ])
    end
  end
end
