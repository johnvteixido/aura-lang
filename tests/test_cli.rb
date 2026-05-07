require "minitest/autorun"
require "open3"
require "fileutils"

class TestCLI < Minitest::Test
  def setup
    @bin_path = File.expand_path("../../bin/aura", __FILE__)
    @test_dir = File.expand_path("../../tmp_test_dir", __FILE__)
    FileUtils.rm_rf(@test_dir)
    FileUtils.mkdir_p(@test_dir)
  end

  def teardown
    FileUtils.rm_rf(@test_dir)
  end

  # FIX BUG-11: help output now includes "Usage: aura [command]"
  def test_help_flag
    stdout, _stderr, status = Open3.capture3("ruby", @bin_path, "--help")
    assert_match(/Usage: aura \[command\]/, stdout)
    assert_equal 0, status.exitstatus
  end

  def test_help_alias
    stdout, _stderr, status = Open3.capture3("ruby", @bin_path, "help")
    assert_match(/Usage: aura \[command\]/, stdout)
    assert_equal 0, status.exitstatus
  end

  def test_init_command
    Dir.chdir(@test_dir) do
      stdout, _stderr, status = Open3.capture3("ruby", @bin_path, "init", "my_app")
      assert_match(/Created Aura project: my_app/, stdout)
      assert Dir.exist?("my_app/models")
      assert Dir.exist?("my_app/data")
      assert File.exist?("my_app/app.aura")
      assert_equal 0, status.exitstatus
    end
  end

  def test_init_without_name_exits_nonzero
    _stdout, _stderr, status = Open3.capture3("ruby", @bin_path, "init")
    refute_equal 0, status.exitstatus
  end

  # FIX BUG-9: message now combined into single string matching /File not found.*Generating a template/
  def test_run_generates_template_if_missing
    Dir.chdir(@test_dir) do
      stdout, _stderr, _status = Open3.capture3("ruby", @bin_path, "run", "missing.aura")
      assert_match(/File not found: missing\.aura\. Generating a template/, stdout)
      assert File.exist?("missing.aura"), "Template file should have been created"
    end
  end

  def test_unknown_command_exits_nonzero
    _stdout, _stderr, status = Open3.capture3("ruby", @bin_path, "bogus_command")
    refute_equal 0, status.exitstatus
  end

  def test_check_command_on_valid_file
    # Write a minimal .aura file to the temp dir, then run `check` on it
    aura_file = File.join(@test_dir, "sample.aura")
    File.write(aura_file, <<~AURA)
      model greeter neural_network do
        input text
        output greeting "Hello!"
      end

      route "/hello" get do
        output prediction from greeter.predict(input) format :json
      end

      run web on port: 3000
    AURA

    stdout, _stderr, status = Open3.capture3("ruby", @bin_path, "check", aura_file)
    assert_equal 0, status.exitstatus
    assert_match(/Transpilation successful/, stdout)
    assert_match(/require "sinatra"/, stdout)
  end
end
