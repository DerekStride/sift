# frozen_string_literal: true

module Sift
  module CLI
    module Queue
      module Formatters
        private

        def print_item_summary(item)
          status_color = status_color_code(item.status)
          source_types = item.sources.map(&:type).tally.map { |t, c| c > 1 ? "#{t}:#{c}" : t }.join(",")

          if cli_ui_available?
            stdout.puts ::CLI::UI.fmt(
              "{{bold:#{item.id}}}  #{status_color}  {{gray:#{source_types}}}  {{gray:#{item.created_at}}}"
            )
          else
            stdout.puts "#{item.id}  [#{item.status}]  #{source_types}  #{item.created_at}"
          end
        end

        def print_item_detail(item)
          if cli_ui_available?
            ::CLI::UI::Frame.open("{{bold:Item #{item.id}}}", color: :blue, to: stdout) do
              stdout.puts ::CLI::UI.fmt("{{bold:Status:}} #{status_color_code(item.status)}")
              stdout.puts ::CLI::UI.fmt("{{bold:Created:}} {{gray:#{item.created_at}}}")
              stdout.puts ::CLI::UI.fmt("{{bold:Updated:}} {{gray:#{item.updated_at}}}")
              stdout.puts ::CLI::UI.fmt("{{bold:Session:}} {{gray:#{item.session_id || "none"}}}")

              if item.metadata && !item.metadata.empty?
                stdout.puts ::CLI::UI.fmt("{{bold:Metadata:}}")
                item.metadata.each do |k, v|
                  stdout.puts ::CLI::UI.fmt("  {{cyan:#{k}:}} #{v}")
                end
              end

              stdout.puts ::CLI::UI.fmt("{{bold:Sources:}} (#{item.sources.length})")
              item.sources.each_with_index do |source, i|
                print_source(source, i)
              end
            end
          else
            stdout.puts "Item: #{item.id}"
            stdout.puts "Status: #{item.status}"
            stdout.puts "Created: #{item.created_at}"
            stdout.puts "Updated: #{item.updated_at}"
            stdout.puts "Session: #{item.session_id || "none"}"

            if item.metadata && !item.metadata.empty?
              stdout.puts "Metadata:"
              item.metadata.each do |k, v|
                stdout.puts "  #{k}: #{v}"
              end
            end

            stdout.puts "Sources: (#{item.sources.length})"
            item.sources.each_with_index do |source, i|
              print_source(source, i)
            end
          end
        end

        def print_source(source, index)
          type_str = source.type
          location = source.path || (source.content ? "[inline]" : "[empty]")

          if cli_ui_available?
            stdout.puts ::CLI::UI.fmt("  {{yellow:[#{index}]}} {{bold:#{type_str}}} {{gray:#{location}}}")
            if source.content && !source.path
              preview = source.content.lines.first(3).map(&:chomp).join("\n")
              preview += "\n..." if source.content.lines.length > 3
              stdout.puts ::CLI::UI.fmt("      {{gray:#{preview}}}")
            end
          else
            stdout.puts "  [#{index}] #{type_str}: #{location}"
            if source.content && !source.path
              preview = source.content.lines.first(3).map(&:chomp).join("\n      ")
              preview += "\n      ..." if source.content.lines.length > 3
              stdout.puts "      #{preview}"
            end
          end
        end

        def status_color_code(status)
          if cli_ui_available?
            case status
            when "pending" then "{{yellow:#{status}}}"
            when "in_progress" then "{{blue:#{status}}}"
            when "closed" then "{{green:#{status}}}"
            else "{{gray:#{status}}}"
            end
          else
            "[#{status}]"
          end
        end
      end
    end
  end
end
