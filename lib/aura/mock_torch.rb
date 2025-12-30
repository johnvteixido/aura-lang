# lib/aura/mock_torch.rb
module Torch
  class Tensor
    attr_reader :data

    def initialize(data)
      @data = data
    end

    def self.randn(*dims)
      new(Array.new(dims.reduce(:*) || 1) { rand(-1.0..1.0) })
    end

    def self.tensor(data)
      new(data)
    end

    def to(device); self; end

    def argmax(dim)
      Tensor.new([@data.each_with_index.max_by { |v, _| v }[1]])
    end
  end

  module NN
    class Module
      def to(device); self; end
      def parameters; []; end
    end

    class Sequential < Module
      def initialize(*layers)
        @layers = layers
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
        # Mock linear transformation
        Tensor.new(Array.new(@out) { rand(-1.0..1.0) })
      end
    end

    class ReLU < Module
      def call(input); input; end
    end

    class Softmax < Module
      def initialize(dim:); end
      def call(input); input; end
    end

    class Dropout < Module
      def initialize(p:); @p = p; end
      def call(input); input; end
    end

    class CrossEntropyLoss < Module; end
  end

  module Optim
    class Adam
      def initialize(params, lr:); end
      def zero_grad; end
      def step; end
    end
  end

  def self.cuda_available?
    false
  end
end
