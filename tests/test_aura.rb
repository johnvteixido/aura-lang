require "minitest/autorun"
require "aura"

class TestAura < Minitest::Test
  def test_parse_simple
    source = <<~AURA
      model test neural_network do
        input shape(1)
        output units: 1, activation: :relu
      end
    AURA
    ast = Aura.parse(source)
    assert ast
  end
end
