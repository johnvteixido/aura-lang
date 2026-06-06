require "minitest/autorun"
require_relative "../lib/aura"

# The diagnostics layer turns raw Parslet failures into Aura::ParseError with
# line/column, and a semantic pass rejects references to undefined models.
class TestDiagnostics < Minitest::Test
  def test_parse_error_carries_line_number
    bad = "model x neural_network do\n  not a real directive\nend\n"
    error = assert_raises(Aura::ParseError) { Aura.transpile(bad) }
    refute_nil error.line, "ParseError should carry a line number"
    assert_match(/line \d+/, error.message)
  end

  def test_undefined_model_in_train_raises_semantic_error
    source = <<~AURA
      model real_one neural_network do
        input shape(10)
        output units: 2, activation: :relu
      end

      train ghost on "data" do
        epochs 1
      end
    AURA
    error = assert_raises(Aura::SemanticError) { Aura.transpile(source) }
    assert_match(/ghost/, error.message)
  end

  def test_undefined_model_in_route_raises_semantic_error
    source = <<~AURA
      route "/x" post do
        output prediction from missing.predict(input)
      end

      run web on port: 3000
    AURA
    assert_raises(Aura::SemanticError) { Aura.transpile(source) }
  end

  def test_valid_program_does_not_raise_or_print
    source = <<~AURA
      model m neural_network do
        input shape(10)
        output units: 2, activation: :softmax
      end

      route "/m" post do
        output prediction from m.predict(input) format :json
      end

      run web on port: 3000
    AURA
    assert_silent { Aura.transpile(source) }
  end
end
