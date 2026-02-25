# frozen_string_literal: true

require "lipgloss"

module Sift
  module TUI
    # Pure function: item → styled card string.
    # No side effects — safe to call from view.
    module Card
      module_function

      def render(item, position: nil, total: nil, width: 80)
        title_line = build_title(item, position: position, total: total)
        body = build_body(item)

        content = body.empty? ? "" : "\n#{body}\n"

        card_style = Styles::CARD_BORDER.width([width - 2, 40].max)
        card_style.render("#{title_line}#{content}")
      end

      def build_title(item, position: nil, total: nil)
        id_str = Styles::CARD_TITLE.render(item.id)
        title = item.respond_to?(:title) && item.title ? " #{item.title}" : ""
        pos = position && total ? " #{Styles::CARD_POSITION.render("[#{position}/#{total}]")}" : ""
        "#{id_str}#{title}#{pos}"
      end

      def build_body(item)
        lines = []

        grouped = item.sources.group_by(&:type)
        grouped.each do |type, sources|
          lines << "  #{Styles::SOURCE_TYPE.render(type)}"
          sources.each do |source|
            label = source.path || "[inline]"
            lines << "    #{Styles::SOURCE_PATH.render(label)}"
          end
        end

        if item.session_id
          lines << "  #{Styles::SOURCE_TYPE.render("transcript")}"
          lines << "    #{Styles::SOURCE_PATH.render("[session]")}"

          parsed = SessionTranscript.parse(item.session_id)
          if parsed && !parsed[:plan_paths].empty?
            lines << "  #{Styles::SOURCE_TYPE.render("plan")}"
            parsed[:plan_paths].each do |plan_path|
              lines << "    #{Styles::SOURCE_PATH.render(File.basename(plan_path))}"
            end
          end
        end

        lines.join("\n")
      end
    end
  end
end
