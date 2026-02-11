# frozen_string_literal: true

require_relative "../queue_test_helper"

class Sift::CLI::Queue::EditTest < Minitest::Test
  include QueueTestHelper

  def test_edit_set_status
    item = queue.push(sources: [{ type: "text", content: "test" }])

    exit_code = run_command(["edit", item.id, "--set-status", "approved"])

    assert_equal 0, exit_code

    updated = queue.find(item.id)
    assert_equal "approved", updated.status
  end

  def test_edit_set_status_to_all_valid_statuses
    Sift::Queue::VALID_STATUSES.each do |status|
      item = queue.push(sources: [{ type: "text", content: status }])

      @stdout = StringIO.new
      @stderr = StringIO.new

      exit_code = run_command(["edit", item.id, "--set-status", status])

      assert_equal 0, exit_code, "Failed for status: #{status}"
      assert_equal status, queue.find(item.id).status
    end
  end

  def test_edit_invalid_status_returns_error
    item = queue.push(sources: [{ type: "text", content: "test" }])

    exit_code = run_command(["edit", item.id, "--set-status", "invalid"])

    assert_equal 1, exit_code
    assert_match(/invalid argument/i, stderr_output)
  end

  def test_edit_nonexistent_item_returns_error
    exit_code = run_command(["edit", "xyz", "--set-status", "approved"])

    assert_equal 1, exit_code
    assert_match(/not found/i, stderr_output)
  end

  def test_edit_without_id_returns_error
    exit_code = run_command(["edit", "--set-status", "approved"])

    assert_equal 1, exit_code
    assert_match(/id.*required/i, stderr_output)
  end

  def test_edit_without_changes_returns_error
    item = queue.push(sources: [{ type: "text", content: "test" }])

    exit_code = run_command(["edit", item.id])

    assert_equal 1, exit_code
    assert_match(/no changes/i, stderr_output)
  end
end
