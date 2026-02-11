# frozen_string_literal: true

module Sift
  module CLI
    class SiftCommand < Base
      command_name "sift"
      summary "Interactive review loop for queue items"
      description "Launch the interactive review loop TUI. Reads pending queue items and presents them for human review."
      examples(
        "sift",
        "sift --queue .sift/queue.jsonl",
        "sift --model opus",
        "sift --dry"
      )

      def define_flags(parser, options)
        options[:queue_path] ||= ENV.fetch("SIFT_QUEUE_PATH", DEFAULT_QUEUE_PATH)
        options[:model] ||= "sonnet"

        parser.on("-q", "--queue PATH", "Queue file path (default: #{DEFAULT_QUEUE_PATH})") do |v|
          options[:queue_path] = v
        end
        parser.on("-m", "--model MODEL", "Claude model (default: sonnet)") do |v|
          options[:model] = v
        end
        parser.on("--dry", "Dry mode: skip Claude API calls, print prompts instead") do
          options[:dry] = true
        end
        parser.on("-v", "--version", "Show version") do
          stdout.puts "sift #{Sift::VERSION}"
          exit
        end
        super
      end

      def execute
        queue = Sift::Queue.new(options[:queue_path])
        Sift::ReviewLoop.new(queue: queue, model: options[:model], dry: options[:dry]).run
        0
      end
    end
  end
end
