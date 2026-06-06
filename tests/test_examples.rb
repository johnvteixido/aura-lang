require "minitest/autorun"
require_relative "../lib/aura"

# Acceptance: every shipped .aura file (and the scaffold template) must parse
# and transpile to Ruby that the VM can actually compile. This catches codegen
# regressions that string-matching tests miss. We compile (not run) the output,
# so no Torch install or server boot is required.
class TestExamples < Minitest::Test
  EXAMPLE_FILES =
    Dir[File.expand_path("../examples/*.aura", __dir__)] +
    [File.expand_path("stress_test.aura", __dir__)]

  EXAMPLE_FILES.each do |path|
    name = File.basename(path, ".aura")
    define_method(:"test_#{name}_transpiles_to_compilable_ruby") do
      code = Aura.transpile(File.read(path, encoding: "UTF-8"))
      assert RubyVM::InstructionSequence.compile(code),
             "Generated Ruby for #{name} should compile"
      assert_match(/require "sinatra"/, code)
    end
  end

  def test_starter_template_is_valid_aura
    code = Aura.transpile(Aura::STARTER_TEMPLATE)
    assert RubyVM::InstructionSequence.compile(code),
           "The scaffold template must transpile to compilable Ruby"
  end
end
