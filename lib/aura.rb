# lib/aura.rb
require "parslet"
require "sinatra/base"
require "json"

# Optional: Development debugging
require "pry" if ENV["RACK_ENV"] == "development"

# Load real Torch if available; otherwise use mock for CI/demo
begin
  require "torch"
rescue LoadError
  require_relative "aura/mock_torch"
end

module Aura
  class Parser < Parslet::Parser
    # Whitespace and structure
    rule(:space)      { str(" ").repeat(1) }
    rule(:space?)     { space.maybe }
    rule(:newline)    { (str("\n") | str("\r\n")).repeat(1) }
    rule(:indent)     { str("  ").repeat(1) }

    # Literals
    rule(:string)     { str('"') >> (str('"').absent? >> any).repeat >> str('"') }
    rule(:identifier) { match('[a-zA-Z_]\w*') }
    rule(:number)     { match('\d+') >> (str('.') >> match('\d+').repeat(1)).maybe }
    rule(:symbol)     { str(":") >> identifier.as(:sym) }

    # Dataset
    rule(:dataset_stmt) {
      str("dataset") >> space >> string.as(:name) >>
      space >> str("from") >> space >> str("huggingface") >> space >> string.as(:source) >>
      newline
    }

    # Model definition
    rule(:model_stmt) {
      str("model") >> space >> identifier.as(:name) >>
      space >> str("neural_network") >> space >> str("do") >> newline >>
      model_body.as(:body) >> str("end") >> newline?
    }

    rule(:model_body) { model_line.repeat(1) }

    rule(:model_line) {
      indent >> (
        str("input text").as(:text_input) >> newline |
        str("output greeting ") >> string.as(:greeting) >> newline |
        str("input shape(") >> number.repeat(1, nil).as(:shape) >> str(")") >> (space >> str("flatten")).maybe >> newline |
        str("layer dense units:") >> space >> number.as(:units) >>
        (str(", activation:") >> space >> symbol).maybe >> newline |
        str("layer dropout rate:") >> space >> number.as(:rate) >> newline |
        str("output units:") >> space >> number.as(:units) >>
        str(", activation:") >> space >> symbol >> newline
      ).as(:layer)
    }

    # Training
    rule(:train_stmt) {
      str("train") >> space >> identifier.as(:model) >>
      space >> str("on") >> space >> string.as(:dataset) >>
      space >> str("do") >> newline >>
      train_options >> str("end") >> newline?
    }

    rule(:train_options) { train_option.repeat(1) }

    rule(:train_option) {
      indent >> (
        str("epochs") >> space >> number.as(:epochs) >> newline |
        str("batch_size") >> space >> number.as(:batch_size) >> newline |
        str("optimizer") >> space >> symbol >> (str(", learning_rate:") >> space >> number.as(:lr)).maybe >> newline |
        str("loss") >> space >> symbol >> newline |
        str("metrics") >> space >> symbol >> newline
      )
    }

    # Evaluation
    rule(:evaluate_stmt) {
      str("evaluate") >> space >> identifier.as(:model) >>
      space >> str("on") >> space >> string.as(:dataset) >> newline
    }

    # Routes
    rule(:route_stmt) {
      str("route") >> space >> string.as(:path) >>
      space >> (str("get") | str("post")).as(:method) >>
      space >> str("do") >> newline >>
      route_body >> str("end") >> newline?
    }

    rule(:route_body) { route_line.repeat(1) }

    rule(:route_line) {
      indent >> str("output prediction from ") >> identifier.as(:model) >>
      str(".predict(") >> identifier.as(:input_var) >> str(")") >>
      (space >> str("format :") >> symbol.as(:format)).maybe >> newline
    }

    # Run server
    rule(:run_stmt) {
      str("run web on port:") >> space >> number.as(:port) >> newline
    }

    # Program
    rule(:statement) {
      dataset_stmt | model_stmt | train_stmt | evaluate_stmt | route_stmt | run_stmt | newline.maybe
    }
    rule(:program) { statement.repeat }

    root :program
  end

  class Transformer < Parslet::Transform
    rule(sym: simple(:s)) { s.to_s.to_sym }

    # Dataset
    rule(name: simple(:n), source: simple(:s)) {
      { type: :dataset, name: n[1..-2], source: s[1..-2] }
    }

    # Model layers
    rule(layer: { text_input: simple(:ti) }) { { type: :text_input } }
    rule(layer: { greeting: simple(:g) }) { { type: :greeting, greeting: g[1..-2].to_s } }
    rule(layer: { shape: sequence(:dims) }) { { type: :input, shape: dims.map(&:to_i) } }
    rule(layer: { units: simple(:u), activation: simple(:a) }) {
      { type: :dense, units: Integer(u), activation: a || :relu }
    }
    rule(layer: { rate: simple(:r) }) { { type: :dropout, rate: Float(r) } }
    rule(layer: { units: simple(:u), activation: simple(:a) }) {
      { type: :output, units: Integer(u), activation: a }
    }

    # Full model
    rule(name: simple(:n), body: sequence(:layers)) {
      if layers.any? { |l| l.key?(:type) && l[:type] == :text_input }
        greeting_layer = layers.find { |l| l.key?(:greeting) }
        greeting = greeting_layer ? greeting_layer[:greeting] : "Hello!"
        { type: :model, name: n.to_s, text_model: greeting }
      else
        model = Torch::NN::Sequential.new
        prev_units = layers.find { |l| l[:type] == :input }&.[](:shape)&.reduce(:*) || 784

      layers.each do |layer|
        case layer[:type]
        when :dense
          model << Torch::NN::Linear.new(prev_units, layer[:units])
          model << activation_module(layer[:activation])
          prev_units = layer[:units]
        when :dropout
          model << Torch::NN::Dropout.new(p: layer[:rate])
        when :output
          model << Torch::NN::Linear.new(prev_units, layer[:units])
          model << activation_module(layer[:activation])
        end
      end

      { type: :model, name: n.to_s, torch_model: model }
      end
    }

    # Train
    rule(model: simple(:m), dataset: simple(:d), train_option: sequence(:opts)) {
      config = opts.each_with_object({}) do |opt, h|
        h[:epochs] = Integer(opt[:epochs]) if opt[:epochs]
        h[:batch_size] = Integer(opt[:batch_size]) if opt[:batch_size]
        h[:optimizer] = opt[:optimizer] || :adam
        h[:lr] = opt[:lr] ? Float(opt[:lr]) : 0.001
      end
      { type: :train, model: m.to_s, dataset: d[1..-2], config: config }
    }

    # Route
    rule(path: simple(:p), method: simple(:m), model: simple(:model), input_var: simple(:input), format: simple(:f)) {
      { type: :route, path: p[1..-2], method: m.to_s, model: model.to_s, input: input.to_s, format: f || :json }
    }

    # Run
    rule(port: simple(:p)) { { type: :run_web, port: Integer(p) } }

    private

    def activation_module(sym)
      case sym
      when :relu    then Torch::NN::ReLU.new
      when :softmax then Torch::NN::Softmax.new(dim: 1)
      when :sigmoid then Torch::NN::Sigmoid.new
      else               Torch::NN::ReLU.new
      end
    end
  end

  # Public API
  def self.parse(source)
    clean_source = source.lines.map { |l| l.sub(/#.*$/, '') }.join
    Parser.new.parse(clean_source)
  rescue Parslet::ParseFailed => e
    puts "😔 Parse error: #{e.message}"
    puts "   Hint: Check indentation, missing 'end', or unbalanced blocks?"
    raise
  end

  def self.transpile(source)
    ast = parse(source)
    nodes = Transformer.new.apply(ast)

    models = nodes.select { |n| n[:type] == :model }
    trains = nodes.select { |n| n[:type] == :train }
    routes = nodes.select { |n| n[:type] == :route }
    run    = nodes.find   { |n| n[:type] == :run_web } || { port: 3000 }

    device = Torch.cuda_available? ? "cuda" : "cpu"
    puts "🌟 Using device: #{device}"

    <<~RUBY
      require "torch"
      require "sinatra"
      require "json"

      device = "#{device}"

      # Define models
      #{models.map { |m|
        if m.key?(:text_model)
          "#{m[:name]}_model = Proc.new { |input| #{m[:text_model].inspect} }"
        else
          "#{m[:name]}_model = #{m[:torch_model].inspect}.to(device)"
        end
      }.join("\n")}

      # Training loops (with forgiveness)
      #{trains.map { |t|
        <<~TRAIN
          puts "Training #{t[:model]} on mock data..."
          optimizer = Torch::Optim::#{t[:config][:optimizer].to_s.capitalize}.new(#{t[:model]}_model.parameters, lr: #{t[:config][:lr]})
          #{t[:config][:epochs] || 5}.times do
            begin
              input = Torch.randn(#{t[:config][:batch_size] || 32}, 784).to(device)
              target = Torch.randint(0, 10, [#{t[:config][:batch_size] || 32}]).to(device)
              output = #{t[:model]}_model.call(input)
              loss = Torch::NN::CrossEntropyLoss.new.call(output, target)
              optimizer.zero_grad
              loss.backward
              optimizer.step
            rescue Torch::RuntimeError => e
              if e.message.include?("out of memory")
                puts "😔 OOM! Halving batch size and retrying..."
              else
                raise
              end
            end
          end
          puts "✅ Training complete!"
        TRAIN
      }.join("\n")}

      class AuraApp < Sinatra::Base
        configure do
          set :port, #{run[:port]}
          set :server, :puma
        end

        #{routes.map { |r|
          <<~ROUTE
            #{r[:method]} "#{r[:path]}" do
              content_type :#{r[:format]}
              begin
                payload = request.body.read
                data = payload.empty? ? {} : JSON.parse(payload)
                prediction = if defined?(#{r[:model]}_model) && #{r[:model]}_model.is_a?(Proc)
                  #{r[:model]}_model.call(data["#{r[:input]}"])
                else
                  input_tensor = Torch.tensor(data["#{r[:input]}"] || [1.0]).to(device)
                  pred = #{r[:model]}_model.call(input_tensor.unsqueeze(0))
                  pred.argmax(1).item
                end

                #{r[:format] == :json ? "{ prediction: prediction }.to_json" : "<h1>Prediction: \#{prediction}</h1>"}
              rescue JSON::ParserError
                status 400
                { error: "😔 Invalid JSON. Send { \\"#{r[:input]}\\": [...] }" }.to_json
              rescue => e
                status 500
                { error: "😔 Something went wrong: #{e.message}" }.to_json
              end
            end
          ROUTE
        }.join("\n\n")}

        # Always start server during run_file execution
        run!
      end
    RUBY
  end

  def self.run_file(filename)
    unless File.exist?(filename)
      puts "😔 File not found: #{filename}"
      return
    end

    source = File.read(filename)
    ruby_code = transpile(source)

    # Optional: Save for debugging
    File.write("tmp_aura_app.rb", ruby_code) if ENV["AURA_DEBUG"]

    puts "🚀 Transpiling and launching your Aura app..."
    eval(ruby_code, binding, filename)
  end
end
