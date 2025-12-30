# lib/aura.rb
require "parslet"
require "torch"
require "sinatra/base"
require "json"

module Aura
  class Transformer < Parslet::Transform
    rule(int: simple(:i)) { Integer(i) }
    rule(float: simple(:f)) { Float(f) }
    rule(symbol: simple(:s)) { s.to_s.to_sym }
    rule(shape: sequence(:dims)) { dims.map(&:to_i) }

    # Dataset
    rule(name: simple(:name), hf_name: simple(:hf_name), split1: simple(:s1), split2: simple(:s2)) {
      { type: :dataset, name: name[1..-2], hf_name: hf_name[1..-2], splits: [s1, s2].compact }
    }
    rule(name: simple(:name), hf_name: simple(:hf_name)) {
      { type: :dataset, name: name[1..-2], hf_name: hf_name[1..-2], splits: [:train, :test] }
    }

    # Model lines
    rule(units: simple(:u), activation: simple(:a)) { { units: Integer(u), activation: a } }
    rule(units: simple(:u)) { { units: Integer(u), activation: :relu } }
    rule(rate: simple(:r)) { { dropout: Float(r) } }

    # Full model
    rule(name: simple(:name), model_line: sequence(:lines)) {
      # 
      seq = Torch::NN::Sequential.new
      layers.zip(@activations).each do |layer, act|
        seq << layer
        seq << Torch::NN.const_get(act.capitalize).new if act
      end
      @models[name.to_s] = seq
      { type: :model, name: name.to_s }
    }
  end

  class Parser < Parslet::Parser
    
    rule(:space?)     { str(" ").repeat }
    rule(:newline)    { (str("\n") | str("\r\n")).repeat(1) }

    rule(:string)     { str('"') >> (str('"').absent >> any).repeat >> str('"') }
    rule(:identifier) { match('[a-z_]\w*') }
    rule(:number)     { match('[0-9]').repeat(1) >> (str(".") >> match('[0-9]').repeat(1)).maybe }

    rule(:dataset) {
      str("dataset") >> space? >> string.as(:name) >> space? >> str("from") >> space? >>
      str("huggingface") >> space? >> string.as(:hf_name) >> newline
    }

    rule(:model) {
      str("model") >> space? >> identifier.as(:name) >> space? >> str("neural_network") >> space? >> str("do") >> newline >>
      (indent >> model_line).repeat >> str("end")
    }

    rule(:indent)     { str("  ").repeat(1) }
    rule(:model_line) {
      indent >> (
        str("input shape(") >> number.repeat(1, nil).as(:shape) >> str(")") >> newline |
        str("layer dense units:") >> space? >> number.as(:units) >> (str(", activation:") >> space? >> identifier.as(:activation)).maybe >> newline |
        str("layer dropout rate:") >> space? >> number.as(:rate) >> newline |
        str("output units:") >> space? >> number.as(:units) >> str(", activation:") >> space? >> identifier.as(:activation) >> newline
      )
    }

    rule(:train) {
      str("train") >> space? >> identifier.as(:model) >> space? >> str("on") >> space? >> string.as(:dataset) >> space? >> str("do") >> newline >>
      (indent >> train_line).repeat >> str("end")
    }

    rule(:train_line) {
      indent >> (
        str("epochs") >> space? >> number.as(:epochs) >> newline |
        str("batch_size") >> space? >> number.as(:batch_size) >> newline |
        str("optimizer") >> space? >> symbol.as(:optimizer) >> (str(", learning_rate:") >> space? >> number.as(:lr)).maybe >> newline |
        str("loss") >> space? >> symbol.as(:loss) >> newline |
        str("metrics") >> space? >> symbol.as(:metrics) >> newline
      )
    }

    rule(:evaluate) {
      str("evaluate") >> space? >> identifier.as(:model) >> space? >> str("on") >> space? >> string.as(:dataset) >> newline
    }

    rule(:route) {
      str("route") >> space? >> string.as(:path) >> space? >> (str("get") | str("post")).as(:method) >> space? >> str("do") >> newline >>
      (indent >> route_line).repeat >> str("end")
    }

    rule(:route_line) {
      indent >> str("output prediction from ") >> identifier.as(:model) >> str(".predict(input)") >> newline
    }

    rule(:run_web) {
      str("run web on port:") >> space? >> number.as(:port) >> newline
    }

    rule(:statement) { dataset | model | train | evaluate | route | run_web | newline }
    rule(:program)   { statement.repeat }

    root(:program)
  end

  def self.transpile(source)
    ast = Parser.new.parse(source)
    transformer = Transformer.new
    transformer.instance_variable_set(:@models, {})
    transformer.instance_variable_set(:@activations, [])
    transformer.apply(ast)

    # 
    <<~RUBY
      require "torch"
      require "sinatra"

      class AuraApp < Sinatra::Base
        #{generate_routes(transformer.instance_variable_get(:@models))}

        run! if app_file == $0
      end
    RUBY
  end

  def self.generate_routes(models)
    models.map do |name, config|
      <<~ROUTE
        post "/predict" do
          content_type :json
          begin
            # Mock input for demo
            input = Torch.randn(1, 784)
            model = #{name}_model
            output = model.call(input)
            { prediction: output.argmax(1).item }.to_json
          rescue => e
            status 500
            { error: "😔 Something went wrong: #{e.message}. Trying smaller batch next time?" }.to_json
          end
        end
      ROUTE
    end.join("\n")
  end

  def self.run_file(filename)
    source = File.read(filename)
    ruby_code = transpile(source)
    puts "🚀 Transpiled and running your Aura app...\n\n"
    eval(ruby_code)
  end
end
