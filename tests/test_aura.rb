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

  def test_parse_comments
    source = <<~AURA
      # This is a comment
      model test from openai "gpt-3.5" # Inline comment!
      
      route "/" get do
        output greeting "Hi" # Say hi
      end
    AURA
    
    # Aura.parse automatically strips comments before Parslet AST runs
    begin
      ast = Aura.parse(source)
      assert ast
    rescue Exception => e
      flunk "Failed to parse with comments: #{e.message}"
    end
  end
  
  def test_unmatched_syntax_rescue
    source = <<~AURA
      model greeter neural_network do
        input text
      # Missing end!
    AURA
    
    error = assert_raises(RuntimeError) do
      Aura.parse(source)
    end
    
    assert_match(/forgot the `end` closure/, error.message)
  end
end
