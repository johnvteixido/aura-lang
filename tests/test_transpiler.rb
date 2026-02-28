require "minitest/autorun"
require_relative "../lib/aura"

class TestTranspiler < Minitest::Test
  def setup
    @parser = Aura::Parser.new
    @transformer = Aura::Transformer.new
  end

  def transpile_fragment(source)
    ast = @parser.parse(source)
    Aura::Transformer.new.apply(ast)
  end

  def test_neural_network_transpilation
    source = <<~AURA
      model my_net neural_network do
        layer linear in: 10, out: 20
        layer relu
      end
    AURA
    result = transpile_fragment(source)
    
    # Needs to generate Torch::NN::Sequential block
    assert_match(/my_net_model = Torch::NN::Sequential\.new/, result[:models][0][:torch_model])
    assert_match(/Torch::NN::Linear\.new\(10, 20\)/, result[:models][0][:torch_model])
    assert_match(/Torch::NN::ReLU\.new\(\)/, result[:models][0][:torch_model])
  end

  def test_openai_llm_transpilation
    source = <<~AURA
      model assistant from openai "gpt-4o"
    AURA
    
    ast = @parser.parse(source)
    # The transformer transforms models, route, training at the route level, but 
    # we can verify the AST mapping directly if the transformer requires a full document.
    assert_equal "assistant", ast.first[:type] == :model ? ast.first[:name] : ast.first[:name]
    assert_equal "gpt-4o", ast.first[:llm_model]
    
    # Transpile full doc
    full_source = <<~AURA
      model assistant from openai "gpt-4o"
      route "/chat" post do
        output prediction from assistant.predict(message) format :json
      end
    AURA
    
    ruby_code = Aura.transpile(full_source)
    assert_match(/api_key = ENV\["OPENAI_API_KEY"\]/, ruby_code)
    assert_match(/https:\/\/api\.openai\.com\/v1\/chat\/completions/, ruby_code)
    assert_match(/"gpt-4o"/, ruby_code)
  end
  
  # Stub for ollama transpilation test to be implemented with the feature
  def test_ollama_llm_transpilation
    # To be implemented
  end
end
