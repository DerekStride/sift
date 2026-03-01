# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "support/fake_git"

class Sift::TUI::AppTest < Minitest::Test
  include TestHelpers

  def setup
    @tmpdir = create_temp_dir
    @queue_path = create_temp_queue_path(@tmpdir)
    @queue = Sift::Queue.new(@queue_path)
  end

  def teardown
    FileUtils.rm_rf(@tmpdir)
  end

  # --- init tests ---

  def test_init_quits_with_empty_queue
    app = build_app
    _model, cmd = app.init

    assert_instance_of Bubbletea::QuitCommand, cmd
  end

  def test_init_starts_with_reviewing_mode
    @queue.push(sources: [{ type: "text", content: "test" }])
    app = build_app
    app.init

    assert_equal :reviewing, app.mode.name
    assert_equal 1, app.items.size
  ensure
    app&.send(:stop_async_reactor)
  end

  # --- view rendering tests ---

  def test_view_reviewing_renders_card
    @queue.push(sources: [{ type: "text", content: "test" }])
    app = build_app
    app.init
    output = app.view

    assert_includes output, "text"
    assert_includes output, "[inline]"
    assert_includes output, "view"
    assert_includes output, "agent"
    assert_includes output, "close"
    assert_includes output, "quit"
  ensure
    app&.send(:stop_async_reactor)
  end

  def test_view_reviewing_shows_position_with_multiple_items
    @queue.push(sources: [{ type: "text", content: "first" }])
    @queue.push(sources: [{ type: "text", content: "second" }])
    app = build_app
    app.init
    output = app.view

    assert_includes output, "[1/2]"
    assert_includes output, "next"
    assert_includes output, "prev"
  ensure
    app&.send(:stop_async_reactor)
  end

  def test_view_reviewing_hides_nav_with_single_item
    @queue.push(sources: [{ type: "text", content: "only" }])
    app = build_app
    app.init
    output = app.view

    refute_includes output, "next"
    refute_includes output, "prev"
  ensure
    app&.send(:stop_async_reactor)
  end

  def test_view_reviewing_shows_status_bar
    @queue.push(sources: [{ type: "text", content: "test" }])
    app = build_app
    app.init
    output = app.view

    assert_includes output, "pending"
  ensure
    app&.send(:stop_async_reactor)
  end

  def test_view_reviewing_shows_flash
    @queue.push(sources: [{ type: "text", content: "test" }])
    app = build_app
    app.init
    app.send(:set_flash, "Test notification", :success)
    output = app.view

    assert_includes output, "Test notification"
  ensure
    app&.send(:stop_async_reactor)
  end

  # --- Card rendering tests ---

  def test_card_groups_sources_by_type
    @queue.push(sources: [
      { type: "diff", path: "a.rb" },
      { type: "diff", path: "b.rb" },
      { type: "file", path: "c.rb" },
      { type: "text", content: "notes" },
    ])
    app = build_app
    app.init
    output = app.view

    assert_includes output, "diff"
    assert_includes output, "a.rb"
    assert_includes output, "b.rb"
    assert_includes output, "file"
    assert_includes output, "c.rb"
    assert_includes output, "text"
    assert_includes output, "[inline]"
  ensure
    app&.send(:stop_async_reactor)
  end

  def test_card_shows_transcript_when_session_id_present
    item = @queue.push(
      sources: [{ type: "text", content: "test" }],
      session_id: "some-session",
    )
    app = build_app
    app.init
    output = app.view

    assert_includes output, "transcript"
    assert_includes output, "[session]"
  ensure
    app&.send(:stop_async_reactor)
  end

  # --- key handling tests (reviewing mode) ---

  def test_key_n_advances_index
    @queue.push(sources: [{ type: "text", content: "first" }])
    @queue.push(sources: [{ type: "text", content: "second" }])
    app = build_app
    app.init

    key = make_key("n")
    app.update(key)

    assert_equal 1, app.index
  ensure
    app&.send(:stop_async_reactor)
  end

  def test_key_p_goes_back
    @queue.push(sources: [{ type: "text", content: "first" }])
    @queue.push(sources: [{ type: "text", content: "second" }])
    app = build_app
    app.init
    app.update(make_key("n")) # go to index 1

    app.update(make_key("p"))

    assert_equal 0, app.index
  ensure
    app&.send(:stop_async_reactor)
  end

  def test_key_n_ignored_with_single_item
    @queue.push(sources: [{ type: "text", content: "only" }])
    app = build_app
    app.init

    app.update(make_key("n"))

    assert_equal 0, app.index
  ensure
    app&.send(:stop_async_reactor)
  end

  def test_key_c_closes_item
    @queue.push(sources: [{ type: "text", content: "test" }])
    app = build_app
    app.init

    _model, cmd = app.update(make_key("c"))

    # Item closed and no more items → should quit
    assert_instance_of Bubbletea::QuitCommand, cmd
    updated = @queue.find(app.send(:instance_variable_get, :@queue).all.first.id)
    assert_equal "closed", updated.status
  ensure
    app&.send(:stop_async_reactor)
  end

  def test_key_q_returns_quit
    @queue.push(sources: [{ type: "text", content: "test" }])
    app = build_app
    app.init

    _model, cmd = app.update(make_key("q"))

    assert_instance_of Bubbletea::QuitCommand, cmd
  ensure
    app&.send(:stop_async_reactor)
  end

  def test_key_a_enters_prompt_mode
    @queue.push(sources: [{ type: "text", content: "test" }])
    app = build_app
    app.init

    app.update(make_key("a"))

    assert_equal :prompting, app.mode.name
    assert_equal :item_agent, app.prompt_target
  ensure
    app&.send(:stop_async_reactor)
  end

  def test_key_g_enters_general_prompt_mode
    @queue.push(sources: [{ type: "text", content: "test" }])
    app = build_app
    app.init

    app.update(make_key("g"))

    assert_equal :prompting, app.mode.name
    assert_equal :general_agent, app.prompt_target
  ensure
    app&.send(:stop_async_reactor)
  end

  # --- prompt mode tests ---

  def test_esc_cancels_prompt
    @queue.push(sources: [{ type: "text", content: "test" }])
    app = build_app
    app.init
    app.update(make_key("a")) # enter prompt mode

    app.update(make_key("esc"))

    assert_equal :reviewing, app.mode.name
  ensure
    app&.send(:stop_async_reactor)
  end

  # --- view_prompting tests ---

  def test_view_prompting_shows_prompt_ui
    @queue.push(sources: [{ type: "text", content: "test" }])
    app = build_app
    app.init
    app.update(make_key("a")) # enter prompt mode

    output = app.view

    assert_includes output, "Prompt"
    assert_includes output, "Ctrl-G"
    assert_includes output, "Esc"
  ensure
    app&.send(:stop_async_reactor)
  end

  # --- view_waiting tests ---

  def test_view_waiting_shows_waiting_message
    @queue.push(sources: [{ type: "text", content: "test" }])
    app = build_app
    app.init

    # Simulate waiting mode
    app.instance_variable_set(:@mode, Sift::TUI::Keymap::WAITING)
    output = app.view

    assert_includes output, "Waiting"
    assert_includes output, "general"
    assert_includes output, "quit"
  ensure
    app&.send(:stop_async_reactor)
  end

  # --- flash notification tests ---

  def test_flash_clear_message_clears_flash
    @queue.push(sources: [{ type: "text", content: "test" }])
    app = build_app
    app.init
    app.send(:set_flash, "Test message", :info)

    app.update(Sift::TUI::FlashClearMessage.new)

    assert_nil app.flash
  ensure
    app&.send(:stop_async_reactor)
  end

  def test_flash_styles
    @queue.push(sources: [{ type: "text", content: "test" }])
    app = build_app
    app.init

    app.send(:set_flash, "Success", :success)
    output = app.view
    assert_includes output, "✓"

    app.send(:set_flash, "Error", :error)
    output = app.view
    assert_includes output, "✗"

    app.send(:set_flash, "Info", :info)
    output = app.view
    assert_includes output, "●"
  ensure
    app&.send(:stop_async_reactor)
  end

  # --- window size ---

  def test_window_size_message_updates_dimensions
    @queue.push(sources: [{ type: "text", content: "test" }])
    app = build_app
    app.init

    msg = Bubbletea::WindowSizeMessage.new(width: 120, height: 40)
    app.update(msg)

    assert_equal 120, app.width
    assert_equal 40, app.height
  ensure
    app&.send(:stop_async_reactor)
  end

  # --- build_agent_prompt tests ---

  def test_build_agent_prompt_first_turn_includes_sources
    @queue.push(sources: [
      { type: "diff", path: "foo.rb", content: "+new line\n" },
      { type: "file", path: "bar.rb", content: "class Bar; end" },
    ])
    app = build_app
    app.init

    item = app.current_item
    prompt = app.send(:build_agent_prompt, item, "Review this")

    assert_includes prompt, "File: foo.rb"
    assert_includes prompt, "```diff"
    assert_includes prompt, "+new line"
    assert_includes prompt, "File: bar.rb"
    assert_includes prompt, "class Bar; end"
    assert_includes prompt, "Review this"
  ensure
    app&.send(:stop_async_reactor)
  end

  def test_build_agent_prompt_subsequent_turn_sends_only_user_prompt
    @queue.push(
      sources: [{ type: "text", content: "should not appear" }],
      session_id: "existing-session",
    )
    app = build_app
    app.init

    item = app.current_item
    prompt = app.send(:build_agent_prompt, item, "Follow-up question")

    assert_equal "Follow-up question", prompt
    refute_includes prompt, "should not appear"
  ensure
    app&.send(:stop_async_reactor)
  end

  private

  def build_app(dry: true)
    config = Sift::Config.new({}, {})
    config.queue_path = @queue_path
    config.dry = dry
    Sift::TUI::App.new(config: config)
  end

  # Create a KeyMessage for testing.
  # The Bubbletea::KeyMessage constructor depends on the gem internals,
  # so we create a minimal stand-in if needed.
  def make_key(key_string)
    # Bubbletea::KeyMessage.new expects internal args; use duck-typing
    msg = Bubbletea::KeyMessage.allocate
    msg.instance_variable_set(:@key, key_string)
    msg.define_singleton_method(:to_s) { key_string }
    msg.define_singleton_method(:enter?) { key_string == "enter" }
    msg.define_singleton_method(:esc?) { key_string == "esc" }
    msg.define_singleton_method(:backspace?) { key_string == "backspace" }
    msg
  end
end
