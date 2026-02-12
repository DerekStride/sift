# frozen_string_literal: true

require_relative "../queue_test_helper"

class Sift::CLI::Queue::RmTest < Minitest::Test
  include QueueTestHelper

  def test_rm_removes_item
    item = queue.push(sources: [{ type: "text", content: "test" }])

    exit_code = run_command(["rm", item.id])

    assert_equal 0, exit_code
    assert_nil queue.find(item.id)
    assert_match(/#{item.id}/, @stdout)
    assert_match(/removed/i, @stderr)
  end

  def test_rm_nonexistent_item_returns_error
    exit_code = run_command(["rm", "xyz"])

    assert_equal 1, exit_code
    assert_match(/not found/i, @stderr)
  end

  def test_rm_without_id_returns_error
    exit_code = run_command(["rm"])

    assert_equal 1, exit_code
    assert_match(/id.*required/i, @stderr)
  end
end
