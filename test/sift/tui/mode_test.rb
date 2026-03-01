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

  def test_ctrl_c_maps_to_different_handlers_across_modes
    reviewing_action = Sift::TUI::Keymap::REVIEWING.lookup("ctrl+c")
    prompting_action = Sift::TUI::Keymap::PROMPTING.lookup("ctrl+c")

    refute_nil reviewing_action
    refute_nil prompting_action
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

  def test_action_bar_omits_nil_labels
    bar = Sift::TUI::Keymap::REVIEWING.action_bar(categories: [:hidden])

    assert_equal "", bar
  end

  def test_name_returns_mode_name
    assert_equal :reviewing, Sift::TUI::Keymap::REVIEWING.name
    assert_equal :prompting, Sift::TUI::Keymap::PROMPTING.name
    assert_equal :waiting, Sift::TUI::Keymap::WAITING.name
  end
end
