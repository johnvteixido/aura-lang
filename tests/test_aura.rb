require "minitest/autorun"
require_relative "../lib/aura"

class TestAuraFramework < Minitest::Test
  def test_transpilation_of_cnn_model
    source = <<~AURA
      model vision neural_network do
        input shape(28, 28, 1)
        layer conv2d filters: 32, kernel: 3
        layer flatten
        output units: 10, activation: :softmax
      end
    AURA
    
    ruby_code = Aura.transpile(source)
    assert_match(/class VisionModel < Torch::NN::Module/, ruby_code)
    assert_match(/Torch::NN::Conv2d\.new\(1, 32, 3/, ruby_code)
    assert_match(/x\.view\(x\.size\(0\), -1\)/, ruby_code)
  end

  def test_environment_configuration
    source = <<~AURA
      environment production do
        api_key "secret_123"
        port 8080
      end
    AURA
    
    ruby_code = Aura.transpile(source)
    assert_match(/class AuraConfig/, ruby_code)
    assert_match(/api_key: "secret_123"/, ruby_code)
    assert_match(/port: 8080/, ruby_code)
  end

  def test_route_generation
    source = <<~AURA
      model m neural_network do
        input shape(10)
        output units: 2, activation: :relu
      end
      route "/api" post do
        output prediction from m.predict(data)
      end
    AURA
    
    ruby_code = Aura.transpile(source)
    assert_match(/post "\/api" do/, ruby_code)
    assert_match(/input = payload\["data"\]/, ruby_code)
    assert_match(/aura_input_tensor\(input,/, ruby_code)
    assert_match(/m_model\.call\(tensor\)/, ruby_code)
  end
end
