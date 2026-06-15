require "minitest/autorun"
require "open3"
require "tempfile"
require_relative "../lib/aura"

# Unlike the string/compile tests, these actually RUN generated apps and drive
# their routes. Each scenario runs in its own subprocess so classic-Sinatra
# global state and the at-exit server boot don't leak between cases. Torch isn't
# installed, so it's stubbed -- the focus here is route wiring, JSON responses,
# and the boot gate, not numerical correctness.
class TestRuntime < Minitest::Test
  # A method_missing-based Torch/Torchvision stub: every tensor/layer op returns
  # something chainable, so a generated `forward` pass runs end to end.
  TORCH_STUB = <<~'RUBY'
    # Use the stubs below instead of the real native/optional gems (torch needs
    # LibTorch; red-datasets pulls in extra deps). Everything else loads normally.
    module Kernel
      alias_method :aura_real_require, :require
      def require(name)
        return true if %w[torch torchvision datasets].include?(name)
        aura_real_require(name)
      end
    end

    class FakeTensor
      def to_a; [0.0, 1.0]; end
      def item; 1; end
      def size(*); 1; end
      def to(*); self; end
      def method_missing(*); self; end
      def respond_to_missing?(*); true; end
    end
    module Torch
      def self.tensor(*); FakeTensor.new; end
      def self.no_grad; yield if block_given?; end
      def self.save(*); end
      def self.load(*); {}; end
      module CUDA; def self.available?; false; end; end
      module NN
        class Module
          def to(*); self; end
          def train; self; end
          def eval; self; end
          def parameters; []; end
          def call(x); forward(x); end
        end
        module F
          def self.method_missing(*); FakeTensor.new; end
          def self.respond_to_missing?(*); true; end
        end
        %i[Linear Conv2d MaxPool2d BatchNorm1d BatchNorm2d Dropout Embedding].each do |layer|
          const_set(layer, Class.new do
            def initialize(*); end
            def call(*); FakeTensor.new; end
            def to(*); self; end
            def parameters; []; end
          end)
        end
        %i[LSTM GRU].each do |rnn|
          const_set(rnn, Class.new do
            def initialize(*); end
            def call(*); [FakeTensor.new, nil]; end # (output, hidden)
          end)
        end
        %i[CrossEntropyLoss MSELoss BCELoss BCEWithLogitsLoss NLLLoss].each do |loss|
          const_set(loss, Class.new do
            def initialize(*); end
            def call(*); FakeTensor.new; end
          end)
        end
      end
      module Optim
        %i[Adam AdamW SGD RMSprop Adagrad].each do |opt|
          const_set(opt, Class.new do
            def initialize(*); end
            def zero_grad; end
            def step; end
          end)
        end
        module LRScheduler
          %i[StepLR ExponentialLR CosineAnnealingLR].each do |sch|
            const_set(sch, Class.new do
              def initialize(*); end
              def step; end
            end)
          end
        end
      end
    end
    module Torchvision
      module Models
        def self.method_missing(*); Torch::NN::Module.new; end
        def self.respond_to_missing?(*); true; end
      end
    end
    module Datasets
      Record = Struct.new(:pixels, :label)
      class MNIST
        def initialize(*); end
        def each; 4.times { |i| yield Record.new([0, 128, 255], i % 10) }; end
      end
      FashionMNIST = MNIST
      CIFAR = MNIST
    end
  RUBY

  # Disable the classic-Sinatra boot so MockRequest can drive the app in-process.
  MOCK_HEAD = <<~'RUBY'
    require "rack"
    require "rack/mock"
    Sinatra::Application.set(:run, false)
  RUBY

  # Transpile in the parent, then run STUB + generated app + driver as a
  # standalone script in a subprocess. Returns [stdout, stderr, Process::Status].
  def run_generated(aura_source, driver = "", extra_env: {})
    code = Aura.transpile(aura_source)
    file = Tempfile.new(["aura_app", ".rb"])
    file.write("#{TORCH_STUB}\n#{code}\n#{driver}\n")
    file.close
    # Propagate the parent's load path so the child finds sinatra/rack whether
    # they're system gems (local) or bundled (CI under `bundle exec`).
    env = { "RUBYLIB" => $LOAD_PATH.join(File::PATH_SEPARATOR) }.merge(extra_env)
    Open3.capture3(env, "ruby", file.path)
  ensure
    file&.unlink
  end

  def test_text_route_returns_greeting_json
    source = <<~AURA
      model greeter neural_network do
        input text
        output greeting "Hello from Aura runtime!"
      end

      route "/hello" get do
        output prediction from greeter.predict(input) format :json
      end

      run web on port: 3000
    AURA
    driver = MOCK_HEAD + <<~'RUBY'
      res = Rack::MockRequest.new(Sinatra::Application).get("/hello")
      puts "STATUS:#{res.status}"
      puts "BODY:#{res.body}"
    RUBY

    out, err, status = run_generated(source, driver)
    assert status.success?, "generated app should run cleanly. stderr:\n#{err}"
    assert_match(/STATUS:200/, out)
    assert_match(/"greeting"/, out)
    assert_match(/Hello from Aura runtime!/, out)
  end

  def test_torch_route_returns_prediction_json
    source = <<~AURA
      model clf neural_network do
        input shape(28, 28, 1)
        layer conv2d filters: 8, kernel: 3
        layer flatten
        output units: 2, activation: :softmax
      end

      route "/predict" post do
        output prediction from clf.predict(data) format :json
      end

      run web on port: 3000
    AURA
    driver = MOCK_HEAD + <<~'RUBY'
      body = '{"data":[[1.0,2.0,3.0]]}'
      res = Rack::MockRequest.new(Sinatra::Application)
                             .post("/predict", input: body, "CONTENT_TYPE" => "application/json")
      puts "STATUS:#{res.status}"
      puts "BODY:#{res.body}"
    RUBY

    out, err, status = run_generated(source, driver)
    assert status.success?, "generated torch app should run cleanly. stderr:\n#{err}"
    assert_match(/STATUS:200/, out)
    assert_match(/"prediction"/, out)
  end

  def test_llm_app_registers_route_and_predict_method
    source = <<~AURA
      model chatbot from openai "gpt-4"

      route "/chat" post do
        output prediction from chatbot.predict(message) format :json
      end

      run web on port: 3000
    AURA
    # No HTTP call -- just confirm the app loads, the route is registered, and
    # the predict helper exists.
    driver = <<~'RUBY'
      Sinatra::Application.set(:run, false)
      puts "ROUTES:#{Sinatra::Application.routes.keys.sort.join(',')}"
      puts "PREDICT:#{respond_to?(:chatbot_predict, true)}"
    RUBY

    out, err, status = run_generated(source, driver)
    assert status.success?, "generated LLM app should load cleanly. stderr:\n#{err}"
    assert_match(/ROUTES:.*POST/, out)
    assert_match(/PREDICT:true/, out)
  end

  # The boot gate starts the server when serving, but not in training mode.
  def test_run_web_is_gated_on_training_mode
    code = Aura.transpile(<<~AURA)
      model greeter neural_network do
        input text
        output greeting "hi"
      end

      route "/hi" get do
        output prediction from greeter.predict(input)
      end

      run web on port: 4567
    AURA
    assert_match(/set :run, ENV\["AURA_TRAIN"\] != "1"/, code)
  end

  # The training loop actually executes (structurally) in training mode: it runs
  # the optimizer/criterion/scheduler/dataloader steps and exits without serving.
  def test_training_loop_runs_in_train_mode
    source = <<~AURA
      model clf neural_network do
        input shape(28, 28, 1)
        layer conv2d filters: 4, kernel: 3
        layer flatten
        output units: 10, activation: :softmax
      end

      train clf on "mnist" do
        epochs 1
        batch_size 2
        optimizer :adam, learning_rate: 0.01
        scheduler :step_lr
        metrics :accuracy
      end

      run web on port: 3000
    AURA
    out, err, status = run_generated(source, "", extra_env: { "AURA_TRAIN" => "1" })
    assert status.success?, "training run should exit cleanly. stderr:\n#{err}"
    assert_match(%r{Epoch 1/1}, out)
    assert_match(/accuracy/, out)
  end

  # In serving mode (no AURA_TRAIN) the training loop must NOT run.
  def test_training_skipped_when_serving
    source = <<~AURA
      model clf neural_network do
        input shape(10)
        output units: 2, activation: :softmax
      end

      train clf on "mnist" do
        epochs 1
      end

      route "/p" post do
        output prediction from clf.predict(x)
      end

      run web on port: 3000
    AURA
    driver = MOCK_HEAD + <<~'RUBY'
      puts "BOOTED"
    RUBY
    out, _err, status = run_generated(source, driver)
    assert status.success?
    refute_match(/Epoch/, out, "training must not run when serving")
    assert_match(/BOOTED/, out)
  end

  # Torch CUDA check must use the real torch-rb API, not the old wrong one.
  def test_torch_header_uses_correct_cuda_api
    code = Aura.transpile(<<~AURA)
      model clf neural_network do
        input shape(10)
        output units: 2, activation: :softmax
      end

      route "/p" post do
        output prediction from clf.predict(x)
      end

      run web on port: 3000
    AURA
    assert_match(/Torch::CUDA\.available\?/, code)
    refute_match(/Torch\.cuda_available\?/, code)
  end

  # Sequence model: embedding -> LSTM -> output runs end to end (the stub RNN
  # returns the (output, hidden) pair so `out, _ = rnn.call(x)` destructures).
  def test_sequence_model_route_runs
    source = <<~AURA
      model seq neural_network do
        layer embedding vocab: 1000, dim: 32
        layer lstm units: 64
        output units: 2, activation: :softmax
      end

      route "/seq" post do
        output prediction from seq.predict(tokens)
      end

      run web on port: 3000
    AURA
    driver = MOCK_HEAD + <<~'RUBY'
      res = Rack::MockRequest.new(Sinatra::Application)
                             .post("/seq", input: '{"tokens":[[1,2,3]]}', "CONTENT_TYPE" => "application/json")
      puts "STATUS:#{res.status}"
      puts "BODY:#{res.body}"
    RUBY
    out, err, status = run_generated(source, driver)
    assert status.success?, "sequence model app should run. stderr:\n#{err}"
    assert_match(/STATUS:200/, out)
    assert_match(/"prediction"/, out)
  end

  # `as :label` returns class indices instead of raw logits.
  def test_as_label_route_returns_label
    source = <<~AURA
      model clf neural_network do
        input shape(4)
        output units: 3, activation: :softmax
      end

      route "/p" post do
        output prediction from clf.predict(x) as :label
      end

      run web on port: 3000
    AURA
    driver = MOCK_HEAD + <<~'RUBY'
      res = Rack::MockRequest.new(Sinatra::Application)
                             .post("/p", input: '{"x":[[1,2,3,4]]}', "CONTENT_TYPE" => "application/json")
      puts "BODY:#{res.body}"
    RUBY
    out, err, status = run_generated(source, driver)
    assert status.success?, err
    assert_match(/"label"/, out)
  end

  # Auto /health endpoint responds even though it isn't declared in the DSL.
  def test_health_endpoint_responds
    source = <<~AURA
      model greeter neural_network do
        input text
        output greeting "hi"
      end

      route "/hello" get do
        output prediction from greeter.predict(input)
      end

      run web on port: 3000
    AURA
    driver = MOCK_HEAD + <<~'RUBY'
      res = Rack::MockRequest.new(Sinatra::Application).get("/health")
      puts "STATUS:#{res.status}"
      puts "BODY:#{res.body}"
    RUBY
    out, _err, status = run_generated(source, driver)
    assert status.success?
    assert_match(/STATUS:200/, out)
    assert_match(/"status":"ok"/, out)
  end

  # CSV training executes: reads a real CSV and runs the loop in train mode.
  def test_csv_training_runs
    csv = Tempfile.new(["data", ".csv"])
    csv.write("f1,f2,f3,f4,label\n5.1,3.5,1.4,0.2,0\n4.9,3.0,1.4,0.2,0\n6.2,3.4,5.4,2.3,2\n5.9,3.0,5.1,1.8,2\n")
    csv.close
    source = <<~AURA
      model iris neural_network do
        input shape(4)
        output units: 3, activation: :softmax
      end

      train iris on "#{csv.path}" do
        epochs 1
        batch_size 2
      end

      run web on port: 3000
    AURA
    out, err, status = run_generated(source, "", extra_env: { "AURA_TRAIN" => "1" })
    csv.unlink
    assert status.success?, "CSV training should run. stderr:\n#{err}"
    assert_match(%r{Epoch 1/1}, out)
  end
end
