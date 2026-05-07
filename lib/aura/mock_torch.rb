# lib/aura/mock_torch.rb
# Mock implementation of the torch-rb API used for CI / demo environments
# where the native LibTorch library is not available.
module Torch
  class Tensor
    attr_reader :data

    def initialize(data)
      @data = data
    end

    # FIX BUG-5: class method receivers were `new(...)` (Torch module) instead
    # of `Torch::Tensor.new(...)`. Both are now explicit.
    def self.randn(*dims)
      total = dims.flatten.reduce(:*) || 1
      Torch::Tensor.new(Array.new(total) { rand(-1.0..1.0) })
    end

    def self.tensor(data)
      Torch::Tensor.new(Array(data).flatten)
    end

    def to(device); self; end
    def unsqueeze(dim); self; end

    def item
      @data.is_a?(Array) ? @data.first.to_f : @data.to_f
    end

    def backward; end

    def argmax(dim)
      idx = if @data.is_a?(Array) && @data.any?
        @data.each_with_index.max_by { |v, _| v.to_f }&.last || 0
      else
        0
      end
      Torch::Tensor.new([idx])
    end

    def round(digits = 4)
      if @data.is_a?(Array)
        Torch::Tensor.new(@data.map { |v| v.round(digits) })
      else
        @data.round(digits)
      end
    end
  end

  module NN
    class Module
      def to(device); self; end
      def parameters; []; end
    end

    class Sequential < Module
      def initialize(*layers)
        @layers = layers.flatten
      end

      def <<(layer)
        @layers << layer
        self
      end

      def call(input)
        @layers.reduce(input) { |x, layer| layer.call(x) }
      end
      alias forward call
    end

    class Linear < Module
      def initialize(in_features, out_features)
        @in, @out = in_features, out_features
      end

      def call(input)
        Torch::Tensor.new(Array.new(@out) { rand(-1.0..1.0) })
      end
    end

    class ReLU < Module
      def call(input); input; end
    end

    class Softmax < Module
      def initialize(dim:); end
      def call(input); input; end
    end

    class Sigmoid < Module
      def call(input); input; end
    end

    class Dropout < Module
      def initialize(p:); @p = p; end
      def call(input); input; end
    end

    class CrossEntropyLoss < Module
      def call(output, target)
        Torch::Tensor.new([0.5])
      end
    end
  end

  module Optim
    class Adam
      def initialize(params, lr:); @lr = lr; end
      def zero_grad; end
      def step; end
    end

    class Sgd
      def initialize(params, lr:); @lr = lr; end
      def zero_grad; end
      def step; end
    end
  end

  # FIX BUG-6: Use Torch::Tensor.new explicitly
  def self.randn(*dims)
    total = dims.flatten.reduce(:*) || 1
    Torch::Tensor.new(Array.new(total) { rand(-1.0..1.0) })
  end

  def self.randint(low, high, size)
    total_size = size.is_a?(Array) ? size.reduce(:*) : size
    Torch::Tensor.new(Array.new(total_size) { rand(low...high) })
  end

  def self.tensor(data)
    Torch::Tensor.new(Array(data).flatten)
  end

  def self.cuda_available?
    false
  end
end
