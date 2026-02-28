require "minitest/autorun"
require "open3"
require "fileutils"

class TestCLI < Minitest::Test
  def setup
    @bin_path = File.expand_path("../../bin/aura", __FILE__)
    @test_dir = File.expand_path("../../tmp_test_dir", __FILE__)
    FileUtils.rm_rf(@test_dir)
  end

  def teardown
    FileUtils.rm_rf(@test_dir)
  end

  def test_help_flag
    stdout, stderr, status = Open3.capture3("ruby", @bin_path, "--help")
    assert_match(/Usage: aura \[command\]/, stdout)
    assert_equal 0, status.exitstatus
  end

  def test_init_command
    # This command doesn't exist yet, but the test will drive the implementation
    Dir.mkdir(@test_dir) unless Dir.exist?(@test_dir)
    Dir.chdir(@test_dir) do
      stdout, stderr, status = Open3.capture3("ruby", @bin_path, "init", "my_app")
      assert_match(/Created Aura project: my_app/, stdout)
      assert Dir.exist?("my_app/models")
      assert Dir.exist?("my_app/data")
      assert File.exist?("my_app/app.aura")
      assert_equal 0, status.exitstatus
    end
  end

  def test_run_generates_template_if_missing
    Dir.mkdir(@test_dir) unless Dir.exist?(@test_dir)
    Dir.chdir(@test_dir) do
      # Note: The CLI instantly evals this file after creating it, so it might fail
      # ruby evaluation if torch isn't installed. We just want to check if the file
      # gets written to disk. Our CLI prints "File not found" and writes it.
      stdout, stderr, status = Open3.capture3("ruby", @bin_path, "run", "missing.aura")
      assert_match(/File not found: missing\.aura\. Generating a template/, stdout)
      assert File.exist?("missing.aura")
    end
  end
end
