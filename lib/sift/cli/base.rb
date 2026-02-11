# frozen_string_literal: true

require "optparse"
require "logger"

module Sift
  module CLI
    class Base
      class << self
        def command_name(name = nil)
          @command_name = name if name
          @command_name
        end

        def summary(text = nil)
          @summary = text if text
          @summary
        end

        def description(text = nil)
          @description = text if text
          @description || @summary
        end

        def examples(*lines)
          @examples = lines if lines.any?
          @examples || []
        end

        def registered_subcommands
          @registered_subcommands ||= []
        end

        def register_subcommand(klass, category: :core)
          registered_subcommands << { klass: klass, category: category }
        end
      end

      attr_reader :argv, :options, :stdin, :stdout, :stderr, :logger, :parent

      def initialize(argv, parent: nil, stdin: $stdin, stdout: $stdout, stderr: $stderr)
        @argv = argv.dup
        @parent = parent
        @options = {}
        @stdin = stdin
        @stdout = stdout
        @stderr = stderr
        @logger = Logger.new(@stderr, level: Logger::INFO)
        @logger.formatter = proc { |_sev, _dt, _prog, msg| "#{msg}\n" }
      end

      def run
        if subcommands?
          route_subcommand
        else
          run_leaf
        end
      rescue OptionParser::ParseError => e
        stderr.puts "Error: #{e.message}"
        1
      rescue Sift::Queue::Error => e
        stderr.puts "Error: #{e.message}"
        1
      end

      # Subclass overrides to add flags. Must call super at end.
      def define_flags(parser, options)
        if @parent
          parser.separator ""
          parser.separator "INHERITED FLAGS"
          @parent.define_flags(parser, options)
        end
      end

      def execute
        raise NotImplementedError, "#{self.class}#execute not implemented"
      end

      def validate; end

      def full_command_name
        parts = []
        cmd = self
        while cmd
          parts.unshift(cmd.class.command_name) if cmd.class.command_name
          cmd = cmd.parent
        end
        parts.join(" ")
      end

      private

      def subcommands?
        self.class.registered_subcommands.any?
      end

      def route_subcommand
        klass = find_subcommand
        if klass
          klass.new(@argv, parent: self, stdin: stdin, stdout: stdout, stderr: stderr).run
        elsif @argv.empty? || @argv.intersect?(%w[-h --help])
          stdout.puts help_text
          0
        else
          stderr.puts "Unknown command: #{@argv.first}"
          stderr.puts
          stdout.puts help_text
          1
        end
      end

      def find_subcommand
        entries = self.class.registered_subcommands
        @argv.each_with_index do |arg, i|
          entry = entries.find { |s| s[:klass].command_name == arg }
          if entry
            @argv.delete_at(i)
            return entry[:klass]
          end
        end
        nil
      end

      def run_leaf
        parser = build_option_parser
        help_requested = false
        parser.on_tail("-h", "--help", "Show help for command") { help_requested = true }
        parser.parse!(@argv)

        if help_requested
          stdout.puts help_text
          return 0
        end

        validate
        execute
      end

      def build_option_parser
        parser = OptionParser.new
        parser.separator "FLAGS"
        define_flags(parser, @options)
        parser
      end

      def help_text
        HelpRenderer.new(self).render
      end

      def cli_ui_available?
        return @cli_ui_available if defined?(@cli_ui_available)

        @cli_ui_available = begin
          require "cli/ui"
          ::CLI::UI::StdoutRouter.enable unless ::CLI::UI::StdoutRouter.current_id
          true
        rescue LoadError
          false
        end
      end
    end
  end
end
