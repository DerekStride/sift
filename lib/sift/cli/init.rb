# frozen_string_literal: true

module Sift
  module CLI
    class Init < Base
      command_name "init"
      summary "Initialize .sift/ directory and config"
      description "Create the .sift/ directory and a config.yml with all keys commented out as a reference."
      examples "sift init"

      CONFIG_TEMPLATE = <<~YAML
        # Sift configuration
        # Uncomment and modify values to override defaults.

        # agent:
        #   command: claude          # CLI command to invoke agents
        #   flags: []                # Additional CLI flags passed to agent
        #   allowed_tools: []        # Restrict agent to these tools
        #   model: sonnet            # Claude model (sonnet, opus, haiku)
        #   system_prompt:           # Path to system prompt file

        # worktree:
        #   setup_command:           # Command to run when setting up worktree
        #   base_branch: main        # Base branch for git operations

        # queue_path: .sift/queue.jsonl   # Queue file location
        # concurrency: 5                  # Max concurrent agents
        # dry: false                      # Skip Claude API calls
      YAML

      SIFT_DIR = ".sift"
      CONFIG_PATH = File.join(SIFT_DIR, "config.yml")

      def execute
        dir_created = false
        unless Dir.exist?(SIFT_DIR)
          Dir.mkdir(SIFT_DIR)
          dir_created = true
        end

        if File.exist?(CONFIG_PATH)
          puts "#{CONFIG_PATH} already exists"
        else
          File.write(CONFIG_PATH, CONFIG_TEMPLATE)
          puts "created #{CONFIG_PATH}"
        end

        logger.info("created #{SIFT_DIR}/") if dir_created
        0
      end
    end
  end
end
