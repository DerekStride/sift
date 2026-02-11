# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"
require "json"
require "stringio"

# Shared setup for all queue subcommand tests.
# Include in any Minitest::Test that exercises QueueCommand.
module QueueTestHelper
  include TestHelpers

  def setup
    @temp_dir = create_temp_dir
    @queue_path = File.join(@temp_dir, "queue.jsonl")
    @stdout = StringIO.new
    @stderr = StringIO.new
  end

  def teardown
    FileUtils.rm_rf(@temp_dir) if @temp_dir && File.exist?(@temp_dir)
  end

  def run_command(args, stdin_content: nil)
    stdin = stdin_content ? StringIO.new(stdin_content) : StringIO.new
    cmd = Sift::CLI::QueueCommand.new(
      args,
      queue_path: @queue_path,
      stdin: stdin,
      stdout: @stdout,
      stderr: @stderr,
    )
    cmd.run
  end

  def queue
    @queue ||= Sift::Queue.new(@queue_path)
  end

  def stdout_output
    @stdout.string
  end

  def stderr_output
    @stderr.string
  end
end
