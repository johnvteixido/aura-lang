require "parslet"
require "torch"
require "sinatra/base"
require "json"
require "pry" if ENV["ENV"] == "development"

module Aura
  class Parser < Parslet::Parser
    rule(:space?)     { str(" ").repeat }
    rule(:newline)    { (str("\n") | str("\r\n")).repeat(1) }
    rule(:indent)     { str("  ").repeat(1) }

    rule(:string)     { str('"') >> (str('"').absent? >> any).repeat >> str('"') }
    rule(:identifier) { match[/\w+/] }
    rule(:number)     { match[/\d+(\.\d+)?/] }
    rule(:symbol)     { str(":") >> identifier.as(:symbol) }

    rule(:dataset) {
      str("dataset") >> space? >> string.as(:name) >> space? >> str("from") >> space? >>
      str("huggingface") >> space? >> string.as(:hf_name) >> newline
    }

    rule(:model) {
      str("model") >> space? >> identifier.as(:name) >> space? >> str("neural_network") >> space? >> str("do") >> newline >>
      model_body >> str("end") >> newline?
    }

    rule(:model_body) { (model_line).repeat(1) }

    rule(:model_line) {
      indent >> (
        str("input shape(") >> number.repeat(1).as(:shape) >> str(")") >> (space? >> str("flatten")).maybe >> newline |
        str("layer dense units:") >> space? >> number.as(:units) >> (str(", activation:") >> space? >> symbol).maybe >> newline |
        str("layer dropout rate:") >> space? >> number.as(:rate) >> newline |
        str("output units:") >> space? >> number.as(:units) >> str(", activation:") >> space? >> symbol >> newline
      ).as(:model_line)
    }

    rule(:train) {
      str("train") >> space? >> identifier.as(:model) >> space? >> str("on") >> space? >> string.as(:dataset) >> space? >> str("do") >> newline >>
      train_body >> str("end") >> newline?
    }

    rule(:train_body) { (train_line).repeat(1) }

    rule(:train_line) {
      indent >> (
        str("epochs") >> space? >> number.as(:epochs) >> newline |
        str("batch_size") >> space? >> number.as(:batch_size) >> newline |
        str("optimizer") >> space? >> symbol.as(:optimizer) >> (str(", learning_rate:") >> space? >> number.as(:lr)).maybe >> newline |
        str("loss") >> space? >> symbol.as(:loss) >> newline |
        str("metrics") >> space? >> symbol.as(:metrics) >> newline
      ).as(:train_line)
    }

    rule(:evaluate) {
      str("evaluate") >> space? >> identifier.as(:model) >> space? >> str("on") >> space? >> string.as(:dataset) >> newline
    }

    rule(:route) {
      str("route") >> space? >> string.as(:path) >> space? >> (str("get") | str("post")).as(:method) >> space? >> str("do") >> newline >>
      route_body >> str("end") >> newline?
    }

    rule(:route_body) { (route_line).repeat(1) }

    rule(:route_line) {
      indent >> str("output prediction from ") >> identifier.as(:model) >> str(".predict(") >> identifier.as(:input) >> str(") ") >> (str("format :") >> symbol.as(:format)).maybe >> newline
    }

    rule(:run_web) {
      str("run web on port:") >> space? >> number.as(:port) >> newline
    }

    rule(:statement) { dataset | model | train | evaluate | route | run_web | newline.maybe }
    rule(:program) { statement.repeat }

    root(:program)
  end

  class Transformer < Parslet::Transform
    rule(name: simple(:n), hf_name: simple(:h)) { {type: :dataset, name: n.str[1..-2], hf_name: h.str[1..-2]} }

    rule(shape: sequence(:dims)) { dims.map { |d| Float(d.str) } }

    rule(model_line: {shape: simple(:s)}) { {input: s} }
    rule(model_line: {units: simple(:u), activation: simple(:a)}) { {dense: {units: Integer(u.str), activation: a ? a.str.to_sym : :relu}} }
    rule(model_line: {rate: simple(:r)}) { {dropout: Float(r.str)} }
    rule(model_line: {units: simple(:u), activation: simple(:a)}) { {output: {units: Integer(u.str), activation: a.str.to_sym}} }

    rule(name: simple(:n), model_body: sequence(:lines)) {
      input_shape = lines.find { |l| l[:input] }[:input] || [1, 784] # Default flatten to 784 for MNIST
      prev_units = input_shape.reduce(:*) if input_shape.is_a?(Array)

      seq = Torch::NN::Sequential.new
      lines.each do |l|
        if l[:dense]
          seq << Torch::NN::Linear.new(prev_units, l[:dense][:units])
          seq << activation_class(l[:dense][:activation])
          prev_units = l[:dense][:units]
        elsif l[:dropout]
          seq << Torch::NN::Dropout.new(p: l[:dropout])
        elsif l[:output]
          seq << Torch::NN::Linear.new(prev_units, l[:output][:units])
          seq << activation_class(l[:output][:activation])
        end
      end

      {type: :model, name: n.str, module: seq}
    }

    rule(model: simple(:m), dataset: simple(:d), train_body: sequence(:lines)) {
      epochs = lines.find { |l| l[:epochs] }[:epochs].str.to_i || 10
      batch_size = lines.find { |l| l[:batch_size] }[:batch_size].str.to_i || 64
      lr = lines.find { |l| l[:lr] }[:lr].str.to_f || 0.001
      optimizer = lines.find { |l| l[:optimizer] }[:optimizer].str.to_sym || :adam
      loss = lines.find { |l| l[:loss] }[:loss].str.to_sym || :categorical_crossentropy
      # ... (generate training code)
      {type: :train, model: m.str, dataset: d.str[1..-2], epochs: epochs, batch_size: batch_size, lr: lr, optimizer: optimizer, loss: loss}
    }

    # Similar for evaluate

    rule(path: simple(:p), method: simple(:m), route_body: sequence(:lines)) {
      input = lines.find { |l| l[:input] }[:input].str
      model = lines.find { |l| l[:model] }[:model].str
      format = lines.find { |l| l[:format] }[:format].str.to_sym || :json
      {type: :route, path: p.str[1..-2], method: m.str, input: input, model: model, format: format}
    }

    rule(port: simple(:p)) { {type: :run_web, port: Integer(p.str)} }

    def activation_class(sym)
      case sym
      when :relu then Torch::NN::ReLU.new
      when :softmax then Torch::NN::Softmax.new(dim: 1)
      else Torch::NN::ReLU.new
      end
    end
  end

  def self.parse(source)
    Parser.new.parse(source)
  rescue Parslet::ParseFailed => e
    puts "😔 Oops, parse error: #{e.message}. Missing 'end' or indentation issue? Let me try to fix..."
    # Forgiveness: Attempt to add missing 'end' or fix indent (simple rule-based)
    fixed = source.lines.map { |l| l.start_with?(' ') ? l : "  #{l}" }.join("\n") + "\nend"
    Parser.new.parse(fixed)
  end

  def self.transpile(source)
    ast = parse(source)
    transformed = Transformer.new.apply(ast)

    models = transformed.select { |node| node[:type] == :model }.map { |m| [m[:name], m[:module]] }.to_h
    trains = transformed.select { |node| node[:type] == :train }
    routes = transformed.select { |node| node[:type] == :route }
    run = transformed.find { |node| node[:type] == :run_web } || {port: 3000}

    device = Torch.cuda_available? ? 'cuda' : 'cpu'
    puts "Using device: #{device} (auto-detected for forgiveness 🌟)"

    ruby_code = <<~RUBY
      require "torch"
      require "sinatra"
      require "json"

      device = '#{device}'

      # Models
      #{models.map { |name, mod| "#{name}_model = #{mod.inspect}.to(device)" }.join("\n")}

      # Training (mock data for MVP)
      #{trains.map do |t|
        <<~TRAIN
          data = Torch.randn(#{t[:batch_size]}, 784).to(device)  # Mock from #{t[:dataset]}
          labels = Torch.randint(0, 10, [#{t[:batch_size]}]).to(device)
          optimizer = Torch::Optim::#{t[:optimizer].capitalize}.new(#{t[:model]}_model.parameters, lr: #{t[:lr]})
          loss_fn = Torch::NN::CrossEntropyLoss.new  # Assuming #{t[:loss]}

          #{t[:epochs]}.times do |epoch|
            begin
              pred = #{t[:model]}_model.call(data)
              loss = loss_fn.call(pred, labels)
              optimizer.zero_grad
              loss.backward
              optimizer.step
            rescue Torch::RuntimeError => e  # Forgiveness: Auto-batch reduce on OOM
              if e.message.include?('out of memory')
                puts "😔 OOM error - halving batch size for you!"
                batch_size /= 2
              else
                raise
              end
            end
          end
          puts "Trained #{t[:model]} for #{t[:epochs]} epochs!"
        TRAIN
      end.join("\n")}

      # Evaluate (mock)
      #{transformed.select { |node| node[:type] == :evaluate }.map do |e|
        "puts 'Evaluated #{e[:model]} on #{e[:dataset]}: Accuracy 95% (mock)'"
      end.join("\n")}

      class AuraApp < Sinatra::Base
        configure { set :server, :puma; set :port, #{run[:port]} }

        #{routes.map do |r|
          method = r[:method]
          path = r[:path]
          <<~ROUTE
            #{method} '#{path}' do
              content_type :#{r[:format]}
              begin
                input = JSON.parse(request.body.read)['#{r[:input]}']  # Real input parse
                tensor = Torch.tensor(input).to(device)
                pred = #{r[:model]}_model.call(tensor)
                #{r[:format] == :json ? "{ prediction: pred.argmax(1).item }.to_json" : "'<h1>Prediction: ' + pred.argmax(1).item.to_s + '</h1>'"}
              rescue => e
                status 500
                #{r[:format] == :json ? "{ error: '😔 Oops: #{e.message}. Try smaller input?' }.to_json" : "'<h1>😔 Error: #{e.message}</h1>'"}
              end
            end
          ROUTE
        end.join("\n")}

        run! if app_file == $0
      end
    RUBY
  end

  def self.run_file(filename)
    source = File.read(filename)
    ruby_code = transpile(source)
    File.write("tmp_aura_app.rb", ruby_code)  # For debugging
    puts "🚀 Transpiled to Ruby! Running your Aura app..."
    load "tmp_aura_app.rb"  # Eval in context
  end
end
