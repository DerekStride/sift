# frozen_string_literal: true

require "test_helper"
require "stringio"

class Sift::DryClientTest < Minitest::Test
  def setup
    Sift::Log.reset!
    @client = Sift::DryClient.new(model: "opus")
  end

  def teardown
    Sift::Log.reset!
  end

  def test_prompt_returns_result
    result = nil
    capture_io { result = @client.prompt("Hello world") }

    assert_instance_of Sift::Client::Result, result
    assert_includes result.response, "dry mode"
    assert result.session_id.start_with?("dry-")
  end

  def test_prompt_preserves_existing_session_id
    result = nil
    capture_io { result = @client.prompt("Hello", session_id: "existing-session") }

    assert_equal "existing-session", result.session_id
  end

  def test_prompt_logs_details
    _, stderr = with_log_level("DEBUG") do
      capture_io { @client.prompt("Review this code\nMore details", session_id: "sess-1") }
    end

    assert_includes stderr, "[dry] model=opus session=sess-1"
    assert_includes stderr, "[dry] prompt: Review this code"
  end

  def test_prompt_logs_new_session_when_none
    _, stderr = with_log_level("DEBUG") do
      capture_io { @client.prompt("Hello") }
    end

    assert_includes stderr, "session=new"
  end

  def test_analyze_diff_delegates_to_prompt
    result = nil
    _, stderr = with_log_level("DEBUG") do
      capture_io { result = @client.analyze_diff("+foo", file: "bar.rb") }
    end

    assert_instance_of Sift::Client::Result, result
    assert_includes stderr, "File: bar.rb"
  end

  def test_default_model
    client = Sift::DryClient.new
    _, stderr = with_log_level("DEBUG") do
      capture_io { client.prompt("test") }
    end

    assert_includes stderr, "model=default"
  end
end
