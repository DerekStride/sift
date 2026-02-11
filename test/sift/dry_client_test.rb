# frozen_string_literal: true

require "test_helper"
require "stringio"

class Sift::DryClientTest < Minitest::Test
  def setup
    @output = StringIO.new
    @client = Sift::DryClient.new(model: "opus", output: @output)
  end

  def test_prompt_returns_result
    result = @client.prompt("Hello world")

    assert_instance_of Sift::Client::Result, result
    assert_includes result.response, "dry mode"
    assert result.session_id.start_with?("dry-")
  end

  def test_prompt_preserves_existing_session_id
    result = @client.prompt("Hello", session_id: "existing-session")

    assert_equal "existing-session", result.session_id
  end

  def test_prompt_logs_details_to_output
    @client.prompt("Review this code\nMore details", session_id: "sess-1")

    log = @output.string
    assert_includes log, "[dry] model=opus session=sess-1"
    assert_includes log, "[dry] prompt: Review this code"
  end

  def test_prompt_logs_new_session_when_none
    @client.prompt("Hello")

    assert_includes @output.string, "session=new"
  end

  def test_analyze_diff_delegates_to_prompt
    result = @client.analyze_diff("+foo", file: "bar.rb")

    assert_instance_of Sift::Client::Result, result
    assert_includes @output.string, "File: bar.rb"
  end

  def test_default_model
    client = Sift::DryClient.new(output: @output)
    client.prompt("test")

    assert_includes @output.string, "model=default"
  end
end
