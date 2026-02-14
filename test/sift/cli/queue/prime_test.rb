# frozen_string_literal: true

require_relative "../queue_test_helper"

class Sift::CLI::Queue::PrimeTest < Minitest::Test
  include QueueTestHelper

  def test_returns_exit_code_0
    exit_code = run_command(["prime"])

    assert_equal 0, exit_code
  end

  def test_output_includes_sift_description
    run_command(["prime"])

    assert_match(/queue-driven review system/i, @stdout)
  end

  def test_output_includes_sq_list_reference
    run_command(["prime"])

    assert_match(/sq list/, @stdout)
  end

  def test_output_includes_sq_show_reference
    run_command(["prime"])

    assert_match(/sq show/, @stdout)
  end

  def test_output_includes_core_workflow
    run_command(["prime"])

    assert_match(/items enter the queue/i, @stdout)
    assert_match(/transcript is appended/i, @stdout)
  end

  def test_output_includes_auto_generated_flags
    run_command(["prime"])

    # Flags are auto-generated from CLI classes, not hardcoded
    assert_match(/--diff PATH/, @stdout)
    assert_match(/--text STRING/, @stdout)
    assert_match(/--set-status STATUS/, @stdout)
    assert_match(/--json/, @stdout)
  end

  def test_output_includes_help_hint_for_subcommands
    run_command(["prime"])

    assert_match(/sq add --help/, @stdout)
    assert_match(/sq list --help/, @stdout)
  end

end
