# frozen_string_literal: true

require "test_helper"
require "stringio"

# Stub commands for testing the Base class
module StubCommands
  class Child < Sift::CLI::Base
    command_name "greet"
    summary "Say hello"
    description "Greet someone by name"
    examples "testcli greet --name World", "testcli greet --name World --verbose"

    def define_flags(parser, options)
      parser.on("--name NAME", "Name to greet") { |v| options[:name] = v }
      super
    end

    def validate
      raise OptionParser::MissingArgument, "--name is required" unless options[:name]
    end

    def execute
      stdout.puts "Hello, #{options[:name]}!"
      stdout.puts "(verbose)" if options[:verbose]
      0
    end
  end

  class Extra < Sift::CLI::Base
    command_name "farewell"
    summary "Say goodbye"

    def execute
      stdout.puts "Goodbye!"
      0
    end
  end

  class Root < Sift::CLI::Base
    command_name "testcli"
    summary "A test CLI"

    register_subcommand Child, category: :core
    register_subcommand Extra, category: :additional

    def define_flags(parser, options)
      parser.on("--verbose", "Enable verbose output") { options[:verbose] = true }
      super
    end
  end

  class Leaf < Sift::CLI::Base
    command_name "leaf"
    summary "A standalone leaf command"

    def define_flags(parser, options)
      parser.on("--count N", Integer, "Number of times") { |v| options[:count] = v }
      super
    end

    def execute
      stdout.puts "count=#{options[:count]}"
      0
    end
  end
end

class Sift::CLI::BaseTest < Minitest::Test
  def setup
    @stdout = StringIO.new
    @stderr = StringIO.new
  end

  def run_root(argv)
    StubCommands::Root.new(argv, stdin: StringIO.new, stdout: @stdout, stderr: @stderr).run
  end

  def run_leaf(argv)
    StubCommands::Leaf.new(argv, stdin: StringIO.new, stdout: @stdout, stderr: @stderr).run
  end

  def stdout_output
    @stdout.string
  end

  def stderr_output
    @stderr.string
  end

  # --- Subcommand routing ---

  def test_routes_to_subcommand
    exit_code = run_root(["greet", "--name", "World"])

    assert_equal 0, exit_code
    assert_equal "Hello, World!\n", stdout_output
  end

  def test_flags_before_subcommand
    exit_code = run_root(["--verbose", "greet", "--name", "World"])

    assert_equal 0, exit_code
    assert_includes stdout_output, "Hello, World!"
    assert_includes stdout_output, "(verbose)"
  end

  def test_flags_after_subcommand
    exit_code = run_root(["greet", "--verbose", "--name", "World"])

    assert_equal 0, exit_code
    assert_includes stdout_output, "Hello, World!"
    assert_includes stdout_output, "(verbose)"
  end

  def test_parent_flags_flow_to_child_options
    exit_code = run_root(["greet", "--name", "X", "--verbose"])

    assert_equal 0, exit_code
    assert_includes stdout_output, "(verbose)"
  end

  # --- No args / help ---

  def test_no_args_shows_help
    exit_code = run_root([])

    assert_equal 0, exit_code
    assert_includes stdout_output, "testcli"
    assert_includes stdout_output, "CORE COMMANDS"
    assert_includes stdout_output, "greet"
  end

  def test_help_flag_shows_help
    exit_code = run_root(["--help"])

    assert_equal 0, exit_code
    assert_includes stdout_output, "testcli"
  end

  def test_leaf_help_flag
    exit_code = run_root(["greet", "--help"])

    assert_equal 0, exit_code
    assert_includes stdout_output, "FLAGS"
    assert_includes stdout_output, "--name"
    assert_includes stdout_output, "INHERITED FLAGS"
    assert_includes stdout_output, "--verbose"
    assert_includes stdout_output, "EXAMPLES"
    assert_includes stdout_output, "testcli greet --name World"
  end

  # --- Unknown subcommand ---

  def test_unknown_subcommand_returns_error
    exit_code = run_root(["bogus"])

    assert_equal 1, exit_code
    assert_includes stderr_output, "Unknown command: bogus"
    assert_includes stdout_output, "CORE COMMANDS"
  end

  # --- Help structure ---

  def test_help_has_description
    exit_code = run_root(["greet", "--help"])

    assert_equal 0, exit_code
    assert_includes stdout_output, "Greet someone by name"
  end

  def test_help_has_usage
    exit_code = run_root(["greet", "--help"])

    assert_equal 0, exit_code
    assert_includes stdout_output, "USAGE"
    assert_includes stdout_output, "testcli greet [flags]"
  end

  def test_parent_help_has_commands_grouped
    exit_code = run_root([])

    assert_equal 0, exit_code
    assert_includes stdout_output, "CORE COMMANDS"
    assert_includes stdout_output, "greet"
    assert_includes stdout_output, "ADDITIONAL COMMANDS"
    assert_includes stdout_output, "farewell"
  end

  def test_help_has_learn_more
    exit_code = run_root([])

    assert_equal 0, exit_code
    assert_includes stdout_output, "LEARN MORE"
  end

  # --- Error handling ---

  def test_invalid_option_returns_error
    exit_code = run_root(["greet", "--nonexistent"])

    assert_equal 1, exit_code
    assert_includes stderr_output, "Error:"
  end

  def test_validate_failure_returns_error
    exit_code = run_root(["greet"])

    assert_equal 1, exit_code
    assert_includes stderr_output, "Error:"
    assert_includes stderr_output, "--name is required"
  end

  # --- Leaf command (no subcommands) ---

  def test_leaf_command_parses_flags
    exit_code = run_leaf(["--count", "5"])

    assert_equal 0, exit_code
    assert_equal "count=5\n", stdout_output
  end

  def test_leaf_command_help
    exit_code = run_leaf(["--help"])

    assert_equal 0, exit_code
    assert_includes stdout_output, "USAGE"
    assert_includes stdout_output, "leaf [flags]"
    assert_includes stdout_output, "--count"
  end

  def test_leaf_invalid_flag_type
    exit_code = run_leaf(["--count", "abc"])

    assert_equal 1, exit_code
    assert_includes stderr_output, "Error:"
  end

  # --- execute not implemented ---

  def test_execute_not_implemented_raises
    klass = Class.new(Sift::CLI::Base) do
      command_name "noop"
    end

    cmd = klass.new([], stdin: StringIO.new, stdout: @stdout, stderr: @stderr)
    assert_raises(NotImplementedError) { cmd.execute }
  end

  # --- Class-level metadata ---

  def test_command_name
    assert_equal "greet", StubCommands::Child.command_name
  end

  def test_summary
    assert_equal "Say hello", StubCommands::Child.summary
  end

  def test_description_falls_back_to_summary
    assert_equal "Say goodbye", StubCommands::Extra.description
  end

  def test_examples
    assert_equal ["testcli greet --name World", "testcli greet --name World --verbose"],
      StubCommands::Child.examples
  end

  # --- full_command_name ---

  def test_full_command_name_root
    root = StubCommands::Root.new([], stdin: StringIO.new, stdout: @stdout, stderr: @stderr)
    assert_equal "testcli", root.full_command_name
  end

  def test_full_command_name_child
    root = StubCommands::Root.new([], stdin: StringIO.new, stdout: @stdout, stderr: @stderr)
    child = StubCommands::Child.new([], parent: root, stdin: StringIO.new, stdout: @stdout, stderr: @stderr)
    assert_equal "testcli greet", child.full_command_name
  end
end
