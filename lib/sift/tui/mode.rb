# frozen_string_literal: true

require "lipgloss"

module Sift
  module TUI
    class Mode
      KeyAction = Data.define(:key, :label, :color, :category, :handler)

      attr_reader :name

      def initialize(name, actions)
        @name = name
        @actions = actions.freeze
        @dispatch = actions.each_with_object({}) { |a, h| h[a.key] = a }.freeze
      end

      def lookup(key)
        @dispatch[key]
      end

      def action_bar(categories:)
        @actions
          .select { |a| categories.include?(a.category) && a.label }
          .map { |a| render_key(a) }
          .join("  ")
      end

      private

      def render_key(action)
        key_style = Lipgloss::Style.new.foreground(action.color).bold(true)
        "#{key_style.render(action.key)} #{action.label}"
      end
    end
  end
end
