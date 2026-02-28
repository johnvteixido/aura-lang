# tests/test_aura.rb
require "minitest/autorun"
require_relative "../lib/aura"

class TestAura < Minitest::Test
  def test_parse_hello_example
    source = <<~AURA
      model greeter neural_network do
        input text
        output greeting "Hello from Aura! 🌟"
      end

      route "/hello" get do
        output prediction from greeter.predict(input) format :json
      end

      run web on port: 3000
    AURA
    ast = Aura::Parser.new.parse(source)
    assert ast
  end
end
