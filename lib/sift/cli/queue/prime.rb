# frozen_string_literal: true

module Sift
  module CLI
    module Queue
      class Prime < Base
        command_name "prime"
        summary "Output sift workflow context for AI agents"
        examples(
          "sq prime",
          "sq prime --queue .sift/queue.jsonl"
        )

        def define_flags(parser, options)
          parser.on("--full", "Force full CLI output") { options[:full] = true }
          super
        end

        # Generate the prime context as a string. Usable without instantiating the command.
        def self.generate
          parts = []
          parts << <<~MD
            # Sift — Queue-Driven Review System

            Sift is a queue-driven review system where **humans make decisions** and **agents do the work**.

            ## Core Workflow

            1. Items enter the queue via `sq add` (with sources: text, diff, file, directory)
            2. A human launches `sift` to review pending items in the TUI
            3. For each item, the human can view the sources and spawn agents to act on them
            4. When an agent finishes, its transcript is appended as a source on the item

            ## `sq` Commands
          MD

          parts << generate_command_reference

          parts.join("\n")
        end

        def execute
          puts self.class.generate
          0
        end

        def self.generate_command_reference
          lines = []

          QueueCommand.registered_subcommands.each do |entry|
            klass = entry[:klass]
            next if klass == Prime # skip prime itself

            name = klass.command_name
            lines << "### `sq #{name}` — #{klass.summary}\n"
            lines << "```"
            flags_for(klass).each do |flag|
              lines << "  #{flag[:usage]}  #{flag[:desc]}"
            end
            lines << "```"
            lines << ""
            lines << "For more information, use `sq #{name} --help`."
            lines << ""
          end

          lines.join("\n")
        end
        private_class_method :generate_command_reference

        def self.flags_for(klass)
          parent_cmd = QueueCommand.new([])
          cmd = klass.new([], parent: parent_cmd)
          parser = OptionParser.new
          cmd.define_flags(parser, {})

          flags = []
          collect_switches(parser.top, flags)
          flags
        end
        private_class_method :flags_for

        def self.collect_switches(list, flags)
          list.list.each do |item|
            next unless item.is_a?(OptionParser::Switch)

            parts = []
            parts.concat(item.short)
            parts.concat(item.long.map { |l| l.to_s })
            usage = parts.join(", ")

            # Append argument hint from the long form pattern
            if item.respond_to?(:arg) && item.arg
              usage = "#{parts.first}#{item.arg}"
              usage = "#{parts.join(", ")} #{item.arg.strip}" if parts.length > 1
            end

            flags << { usage: usage, desc: item.desc.join(" ") }
          end
        end
        private_class_method :collect_switches
      end
    end
  end
end
