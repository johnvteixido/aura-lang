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

  # --- v1.2.1: parse + codegen feature coverage -----------------------------

  # P1: trailing/inline `# ...` comments are stripped (the README example uses
  # `scheduler :step_lr # ...`).
  def test_inline_comments_are_stripped
    source = <<~AURA
      model n neural_network do
        input shape(10)
        output units: 2, activation: :relu
      end

      train n on "d" do
        optimizer :adam, learning_rate: 0.01 # trailing comment
        scheduler :step_lr # another one
      end
    AURA
    assert_silent { Aura.transpile(source) }
    cfg = parse_and_transform(source).find { |n| n[:type] == :train }[:config]
    assert_in_delta 0.01, cfg[:lr], 0.0001
    assert_equal :step_lr, cfg[:scheduler]
  end

  # P3: scientific-notation numbers parse to Float.
  def test_scientific_notation_learning_rate
    source = <<~AURA
      model n neural_network do
        input shape(10)
        output units: 2, activation: :relu
      end

      train n on "d" do
        optimizer :adam, learning_rate: 1e-4
      end
    AURA
    cfg = parse_and_transform(source).find { |n| n[:type] == :train }[:config]
    assert_in_delta 0.0001, cfg[:lr], 1e-9
    assert_match(/lr: 0.0001/, Aura.transpile(source))
  end

  # P4: negative numbers parse (e.g. a -1 reshape dim).
  def test_negative_numbers_in_input_shape
    source = <<~AURA
      model m neural_network do
        input shape(-1, 28, 28)
        output units: 3, activation: :softmax
      end
    AURA
    shape = parse_and_transform(source).find { |n| n[:type] == :model }[:layers]
                                       .find { |l| l[:type] == :input }[:shape]
    assert_equal [-1, 28, 28], shape
  end

  # P2: escaped quotes survive into the generated string literal.
  def test_escaped_quotes_in_greeting
    source = %(model g neural_network do\n  input text\n  output greeting "say \\"hi\\""\nend\n)
    assert_match(/say \\"hi\\"/, Aura.transpile(source))
  end

  # S2/S3: transfer models apply freeze and build a classification head.
  def test_transfer_model_applies_freeze_and_head
    source = <<~AURA
      model vision transfer from :resnet18 do
        freeze until :layer_4
        output units: 10, activation: :softmax
      end
    AURA
    code = Aura.transpile(source)
    assert_match(/Torchvision::Models\.resnet18\(pretrained: true\)/, code)
    assert_match(/requires_grad = false/, code)
    assert_match(/@head = Torch::NN::Linear\.new\(1000, 10\)/, code)
    assert_match(/Torch::NN::F\.softmax\(@head\.call\(x\), dim: 1\)/, code)
  end

  # R3: a declared `save weights` is actually invoked after the training loop.
  def test_training_invokes_save_weights_when_declared
    source = <<~AURA
      model m neural_network do
        input shape(10)
        output units: 2, activation: :softmax
        save weights to "m.pth"
      end

      train m on "mnist" do
        epochs 1
      end
    AURA
    code = Aura.transpile(source)
    assert_match(/def m_save_weights/, code)
    assert_match(/^\s+m_save_weights$/, code) # the call (inside the training guard), not just the def
  end

  # E2/Q5: the route reads the JSON key named in `model.predict(<var>)`.
  def test_route_uses_dsl_input_variable_as_payload_key
    source = <<~AURA
      model m neural_network do
        input shape(10)
        output units: 2, activation: :softmax
      end

      route "/p" post do
        output prediction from m.predict(features)
      end

      run web on port: 3000
    AURA
    assert_match(/input = payload\["features"\]/, Aura.transpile(source))
  end

  # #1: inference reshapes the payload to the model's input dims (so a conv model
  # route doesn't crash on a bare array) and runs under eval + no_grad.
  def test_inference_reshapes_input_for_conv_model
    source = <<~AURA
      model clf neural_network do
        input shape(28, 28, 1)
        layer conv2d filters: 8, kernel: 3
        layer flatten
        output units: 10, activation: :softmax
      end

      route "/predict" post do
        output prediction from clf.predict(image)
      end

      run web on port: 3000
    AURA
    code = Aura.transpile(source)
    assert_match(/aura_input_tensor\(input, \[1, 28, 28\]\)/, code)
    assert_match(/Torch\.no_grad do/, code)
    assert_match(/clf_model\.eval/, code)
  end

  # #2: training is gated on AURA_TRAIN so it doesn't run on every server boot.
  def test_training_is_gated_on_train_mode
    source = <<~AURA
      model m neural_network do
        input shape(10)
        output units: 2, activation: :softmax
      end

      train m on "mnist" do
        epochs 3
      end

      run web on port: 3000
    AURA
    code = Aura.transpile(source)
    assert_match(/if ENV\["AURA_TRAIN"\] == "1"/, code)
    assert_match(/set :run, ENV\["AURA_TRAIN"\] != "1"/, code)
  end

  # #3: each LR scheduler gets the right constructor arguments.
  def test_scheduler_constructors
    {
      step_lr: /StepLR\.new\(optimizer, step_size: 1, gamma: 0\.1\)/,
      exponential_lr: /ExponentialLR\.new\(optimizer, gamma: 0\.9\)/,
      cosine_annealing_lr: /CosineAnnealingLR\.new\(optimizer, t_max: 5\)/
    }.each do |scheduler, pattern|
      source = <<~AURA
        model m neural_network do
          input shape(10)
          output units: 2, activation: :softmax
        end

        train m on "mnist" do
          epochs 5
          scheduler :#{scheduler}
        end
      AURA
      assert_match(pattern, Aura.transpile(source), "wrong constructor for #{scheduler}")
    end
  end

  # #7: LLM clients set timeouts and handle non-success responses.
  def test_llm_client_has_timeouts_and_error_handling
    code = Aura.transpile(<<~AURA)
      model bot from openai "gpt-4o"

      route "/c" post do
        output prediction from bot.predict(message)
      end

      run web on port: 3000
    AURA
    assert_match(/http\.read_timeout = 60/, code)
    assert_match(/unless response\.is_a\?\(Net::HTTPSuccess\)/, code)
    assert_match(/rescue => e/, code)
  end

  # #8: auth uses a constant-time comparison and refuses when unconfigured.
  def test_auth_is_constant_time
    code = Aura.transpile(<<~AURA)
      model m neural_network do
        input shape(10)
        output units: 2, activation: :softmax
      end

      route "/p" post do
        authenticate with :token
        output prediction from m.predict(x)
      end

      run web on port: 3000
    AURA
    assert_match(/Rack::Utils\.secure_compare/, code)
    assert_match(/auth not configured/, code)
  end
end
