# frozen_string_literal: true

require_relative "queue_test_helper"

class Sift::CLI::QueueCommandTest < Minitest::Test
  include QueueTestHelper

  def test_shows_help_with_no_args
    exit_code = run_command([])

    assert_equal 0, exit_code
    assert_includes @stdout, "USAGE"
    assert_includes @stdout, "sq"
    assert_includes @stdout, "add"
    assert_includes @stdout, "list"
  end

  def test_shows_help_with_help_flag
    exit_code = run_command(["--help"])

    assert_equal 0, exit_code
    assert_includes @stdout, "USAGE"
  end

  def test_unknown_subcommand_returns_error
    exit_code = run_command(["unknown"])

    assert_equal 1, exit_code
    assert_match(/unknown command/i, @stderr)
  end
end
