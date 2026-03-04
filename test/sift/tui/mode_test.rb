# frozen_string_literal: true

require "test_helper"

class Sift::TUI::ModeTest < Minitest::Test
  def test_lookup_returns_key_action
    action = Sift::TUI::Keymap::REVIEWING.lookup("v")

    assert_instance_of Sift::TUI::Mode::KeyAction, action
    assert_equal "v", action.key
    assert_equal "view", action.label
  end

  def test_lookup_returns_nil_for_unknown_key
    assert_nil Sift::TUI::Keymap::REVIEWING.lookup("z")
  end

  def test_mode_isolates_keys
    assert_nil Sift::TUI::Keymap::WAITING.lookup("v")
  end

  def test_ctrl_c_is_registered_in_all_modes
    refute_nil Sift::TUI::Keymap::REVIEWING.lookup("ctrl+c")
    refute_nil Sift::TUI::Keymap::PROMPTING.lookup("ctrl+c")
    refute_nil Sift::TUI::Keymap::WAITING.lookup("ctrl+c")
  end

  def test_ctrl_c_has_different_handlers_across_reviewing_and_prompting
    reviewing_action = Sift::TUI::Keymap::REVIEWING.lookup("ctrl+c")
    prompting_action = Sift::TUI::Keymap::PROMPTING.lookup("ctrl+c")

    # Behavioral difference (quit vs cancel) is verified in app_test.rb;
    # here we just confirm the dispatch table wires distinct handlers.
    refute_equal reviewing_action.handler, prompting_action.handler
  end

  def test_action_bar_filters_by_category
    bar = Sift::TUI::Keymap::REVIEWING.action_bar(categories: [:action])

    assert_includes bar, "view"
    assert_includes bar, "agent"
    assert_includes bar, "close"
    assert_includes bar, "general"
    refute_includes bar, "next"
    refute_includes bar, "prev"
    refute_includes bar, "quit"
  end

  def test_action_bar_includes_nav_category
    bar = Sift::TUI::Keymap::REVIEWING.action_bar(categories: [:nav])

    assert_includes bar, "next"
    assert_includes bar, "prev"
    refute_includes bar, "view"
    refute_includes bar, "quit"
  end

  def test_action_bar_omits_nil_labels
    bar = Sift::TUI::Keymap::REVIEWING.action_bar(categories: [:hidden])

    assert_equal "", bar
  end

  def test_action_bar_for_waiting_mode
    bar = Sift::TUI::Keymap::WAITING.action_bar(categories: [:action, :quit])

    assert_includes bar, "general"
    assert_includes bar, "quit"
    refute_includes bar, "view"
    refute_includes bar, "next"
  end

  def test_name_returns_mode_name
    assert_equal :reviewing, Sift::TUI::Keymap::REVIEWING.name
    assert_equal :prompting, Sift::TUI::Keymap::PROMPTING.name
    assert_equal :waiting, Sift::TUI::Keymap::WAITING.name
  end
end
