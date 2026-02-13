# frozen_string_literal: true

require "test_helper"
require "json"
require "tmpdir"

class Sift::EditorTest < Minitest::Test
  def setup
    @original_editor = ENV["EDITOR"]
    @original_visual = ENV["VISUAL"]
  end

  def teardown
    ENV["EDITOR"] = @original_editor
    ENV["VISUAL"] = @original_visual
  end

  # --- resolve_editor ---

  def test_resolve_editor_uses_editor_env
    ENV["EDITOR"] = "nano"
    editor = Sift::Editor.new(sources: [], item_id: "test")
    assert_equal "nano", editor.resolve_editor
  end

  def test_resolve_editor_falls_back_to_visual
    ENV.delete("EDITOR")
    ENV["VISUAL"] = "emacs"
    editor = Sift::Editor.new(sources: [], item_id: "test")
    assert_equal "emacs", editor.resolve_editor
  end

  def test_resolve_editor_falls_back_to_vi
    ENV.delete("EDITOR")
    ENV.delete("VISUAL")
    editor = Sift::Editor.new(sources: [], item_id: "test")
    assert_equal "vi", editor.resolve_editor
  end

  # --- editor_command ---

  def test_editor_command_adds_wait_for_code
    ENV["EDITOR"] = "code"
    editor = Sift::Editor.new(sources: [], item_id: "test")
    assert_equal ["code", "--wait"], editor.editor_command
  end

  def test_editor_command_adds_wait_for_subl
    ENV["EDITOR"] = "subl"
    editor = Sift::Editor.new(sources: [], item_id: "test")
    assert_equal ["subl", "--wait"], editor.editor_command
  end

  def test_editor_command_adds_tab_flag_for_vim
    ENV["EDITOR"] = "vim"
    editor = Sift::Editor.new(sources: [], item_id: "test")
    assert_equal ["vim", "-p"], editor.editor_command
  end

  def test_editor_command_adds_tab_flag_for_nvim
    ENV["EDITOR"] = "nvim"
    editor = Sift::Editor.new(sources: [], item_id: "test")
    assert_equal ["nvim", "-p"], editor.editor_command
  end

  def test_editor_command_adds_tab_flag_for_vi
    ENV["EDITOR"] = "vi"
    editor = Sift::Editor.new(sources: [], item_id: "test")
    assert_equal ["vi", "-p"], editor.editor_command
  end

  def test_editor_command_no_duplicate_tab_flag
    ENV["EDITOR"] = "nvim -p"
    editor = Sift::Editor.new(sources: [], item_id: "test")
    assert_equal ["nvim", "-p"], editor.editor_command
  end

  def test_editor_command_no_flags_for_nano
    ENV["EDITOR"] = "nano"
    editor = Sift::Editor.new(sources: [], item_id: "test")
    assert_equal ["nano"], editor.editor_command
  end

  def test_editor_command_no_duplicate_wait
    ENV["EDITOR"] = "code --wait"
    editor = Sift::Editor.new(sources: [], item_id: "test")
    assert_equal ["code", "--wait"], editor.editor_command
  end

  # --- collect_paths ---

  def test_collect_paths_diff_source_with_existing_file
    Dir.mktmpdir("sift_test_") do |dir|
      file_path = File.join(dir, "foo.rb")
      File.write(file_path, "original content")

      source = Sift::Queue::Source.new(type: "diff", path: file_path, content: "+new line\n")
      editor = Sift::Editor.new(sources: [source], item_id: "abc")
      paths = editor.collect_paths

      assert_equal 2, paths.length
      assert_equal file_path, paths[0]
      assert paths[1].end_with?(".diff")
      assert_includes paths[1], "sift-abc-foo.rb"
    end
  end

  def test_collect_paths_diff_source_without_path
    source = Sift::Queue::Source.new(type: "diff", content: "+new line\n")
    editor = Sift::Editor.new(sources: [source], item_id: "abc")
    paths = editor.collect_paths

    assert_equal 1, paths.length
    assert paths[0].end_with?(".diff")
    assert_includes paths[0], "sift-abc-changes"
  end

  def test_collect_paths_file_source
    Dir.mktmpdir("sift_test_") do |dir|
      file_path = File.join(dir, "bar.rb")
      File.write(file_path, "class Bar; end")

      source = Sift::Queue::Source.new(type: "file", path: file_path, content: "class Bar; end")
      editor = Sift::Editor.new(sources: [source], item_id: "abc")
      paths = editor.collect_paths

      assert_equal 1, paths.length
      assert_equal file_path, paths[0]
    end
  end

  def test_collect_paths_file_source_missing_file
    source = Sift::Queue::Source.new(type: "file", path: "/nonexistent/bar.rb", content: "class Bar; end")
    editor = Sift::Editor.new(sources: [source], item_id: "abc")
    paths = editor.collect_paths

    assert_empty paths
  end

  def test_collect_paths_text_source
    source = Sift::Queue::Source.new(type: "text", content: "some notes")
    editor = Sift::Editor.new(sources: [source], item_id: "abc")
    paths = editor.collect_paths

    assert_equal 1, paths.length
    assert paths[0].end_with?(".md")
    assert_includes paths[0], "sift-abc"
    assert_equal "some notes", File.read(paths[0])
  end

  def test_collect_paths_with_session_id_renders_transcript
    Dir.mktmpdir("sift_test_") do |dir|
      # Create a fake session JSONL file
      session_id = "test-session"
      slug = Dir.pwd.gsub("/", "-")
      session_dir = File.join(dir, slug)
      FileUtils.mkdir_p(session_dir)
      session_path = File.join(session_dir, "#{session_id}.jsonl")
      File.write(session_path, [
        { "type" => "user", "message" => { "role" => "user", "content" => "Hello" } }.to_json,
        { "type" => "assistant", "message" => { "role" => "assistant", "id" => "m1",
          "content" => [{ "type" => "text", "text" => "Hi there." }] } }.to_json,
      ].join("\n") + "\n")

      # Stub the projects dir so SessionTranscript finds our file
      original_dir = Sift::SessionTranscript::PROJECTS_DIR
      Sift::SessionTranscript.send(:remove_const, :PROJECTS_DIR)
      Sift::SessionTranscript.const_set(:PROJECTS_DIR, dir)

      editor = Sift::Editor.new(sources: [], item_id: "abc", session_id: session_id)
      paths = editor.collect_paths

      assert_equal 1, paths.length
      assert paths[0].end_with?(".md")
      content = File.read(paths[0])
      assert_includes content, "**User:** Hello"
      assert_includes content, "Hi there."
    ensure
      Sift::SessionTranscript.send(:remove_const, :PROJECTS_DIR)
      Sift::SessionTranscript.const_set(:PROJECTS_DIR, original_dir)
    end
  end

  def test_collect_paths_without_session_id_has_no_transcript
    source = Sift::Queue::Source.new(type: "text", content: "just text")
    editor = Sift::Editor.new(sources: [source], item_id: "abc")
    paths = editor.collect_paths

    assert_equal 1, paths.length
    assert paths[0].end_with?(".md")
    assert_equal "just text", File.read(paths[0])
  end

  def test_temp_file_naming
    source = Sift::Queue::Source.new(type: "diff", path: "lib/foo.rb", content: "+line\n")
    editor = Sift::Editor.new(sources: [source], item_id: "x1")
    paths = editor.collect_paths

    temp_path = paths.find { |p| p.end_with?(".diff") }
    assert_includes File.basename(temp_path), "sift-x1-foo.rb.diff"
  end
end
