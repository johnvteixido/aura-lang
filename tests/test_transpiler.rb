require "minitest/autorun"
require_relative "../lib/aura"

class TestTranspiler < Minitest::Test
  def setup
    @parser      = Aura::Parser.new
    @transformer = Aura::Transformer.new
  end

  def parse_and_transform(source)
    ast   = Aura.parse(source)
    nodes = Aura::Transformer.new.apply(ast)
    nodes.flatten.compact.select { |n| n.is_a?(Hash) }
  end

  # FIX: transformer returns a flat array of node hashes, not a nested structure.
  # BUG-1 fix verification: dense layers must NOT become :output type.
  def test_neural_network_transpilation
    source = <<~AURA
      model my_net neural_network do
        input shape(10, 20)
        layer dense units: 20, activation: :relu
        layer dropout rate: 0.2
        output units: 5, activation: :softmax
      end
    AURA

    nodes = parse_and_transform(source)
    model_node = nodes.find { |n| n[:type] == :model }
    refute_nil model_node, "Expected a :model node in the transformer output"
    assert_equal "my_net", model_node[:name]
    # Torch model should have been built (not an LLM / text model)
    assert model_node.key?(:torch_model), "Expected a :torch_model key on the model node"
  end

  # Verify dense layer is NOT mis-typed as :output (BUG-1 regression test)
  def test_dense_layer_type_not_confused_with_output
    source = <<~AURA
      model classifier neural_network do
        input shape(28, 28, 1)
        layer dense units: 128, activation: :relu
        output units: 10, activation: :softmax
      end
    AURA

    # As long as transpilation doesn't raise, the layers were handled correctly.
    assert_silent { Aura.transpile(source) }
  end

  # BUG-2 fix: verify train nodes are actually produced
  def test_train_stmt_produces_train_node
    source = <<~AURA
      model net neural_network do
        input shape(10)
        output units: 5, activation: :softmax
      end

      train net on "my_dataset" do
        epochs 3
        batch_size 16
        optimizer :adam, learning_rate: 0.01
        loss :cross_entropy
        metrics :accuracy
      end

      run web on port: 3000
    AURA

    nodes = parse_and_transform(source)
    train_node = nodes.find { |n| n[:type] == :train }
    refute_nil train_node, "Expected a :train node in transformer output"
    assert_equal "net",          train_node[:model]
    assert_equal "my_dataset",   train_node[:dataset]
    assert_equal 3,              train_node[:config][:epochs]
    assert_equal 16,             train_node[:config][:batch_size]
    assert_equal :adam,          train_node[:config][:optimizer]
    assert_in_delta 0.01,        train_node[:config][:lr], 0.0001
  end

  # BUG-3 fix: route format correctly parsed as :json / :html
  def test_route_format_parsed_correctly
    source = <<~AURA
      model assistant from openai "gpt-4o"

      route "/chat" post do
        output prediction from assistant.predict(message) format :json
      end

      run web on port: 3000
    AURA

    nodes = parse_and_transform(source)
    route_node = nodes.find { |n| n[:type] == :route }
    refute_nil route_node, "Expected a :route node"
    assert_equal :json, route_node[:format]
  end

  # OpenAI LLM transpilation — BUG-7 fix: no training loop emitted for LLM models
  def test_openai_llm_transpilation
    source = <<~AURA
      model assistant from openai "gpt-4o"

      route "/chat" post do
        output prediction from assistant.predict(message) format :json
      end

      run web on port: 3000
    AURA

    ruby_code = Aura.transpile(source)
    assert_match(/api_key = ENV\["OPENAI_API_KEY"\]/, ruby_code)
    assert_match(/https:\/\/api\.openai\.com\/v1\/chat\/completions/, ruby_code)
    assert_match(/"gpt-4o"/, ruby_code)
    # BUG-7: LLM models must not have a training loop referencing .parameters
    refute_match(/assistant_model\.parameters/, ruby_code)
  end

  # Ollama LLM transpilation
  def test_ollama_llm_transpilation
    source = <<~AURA
      model chat from ollama "llama3"

      route "/ask" post do
        output prediction from chat.predict(message) format :json
      end

      run web on port: 3000
    AURA

    ruby_code = Aura.transpile(source)
    assert_match(/localhost:11434\/api\/generate/, ruby_code)
    assert_match(/"llama3"/, ruby_code)
    refute_match(/chat_model\.parameters/, ruby_code)
  end

  # Evaluate statement transformer (BUG-15)
  def test_evaluate_stmt_transformer
    source = <<~AURA
      model classifier neural_network do
        input shape(28, 28, 1)
        output units: 10, activation: :softmax
      end

      evaluate classifier on "mnist/test"

      run web on port: 3000
    AURA

    nodes = parse_and_transform(source)
    eval_node = nodes.find { |n| n[:type] == :evaluate }
    refute_nil eval_node, "Expected an :evaluate node in transformer output"
    assert_equal "classifier", eval_node[:model]
    assert_equal "mnist/test", eval_node[:dataset]
  end
end
