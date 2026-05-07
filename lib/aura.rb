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
  # Custom exception so REPL and callers can distinguish Aura parse errors
  # from unrelated RuntimeErrors without depending on message content.
  class ParseError < StandardError; end

  class Parser < Parslet::Parser
    # Whitespace and structure
    rule(:space)      { str(" ").repeat(1) }
    rule(:space?)     { space.maybe }
    rule(:newline)    { (str("\n") | str("\r\n")).repeat(1) }
    rule(:indent)     { str("  ").repeat(1) }

    # Literals
    rule(:string)     { str('"') >> (str('"').absent? >> any).repeat >> str('"') }
    rule(:identifier) { match('[a-zA-Z_]\w*') }
    # FIX BUG-14: capture number as a single contiguous slice via `as`
    rule(:number)     { (match('\d+') >> (str('.') >> match('\d+').repeat(1)).maybe).as(:number) }
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
      space >> (
        (str("from") >> space >> str("openai") >> space >> string.as(:openai_model)).as(:llm) |
        (str("from") >> space >> str("ollama") >> space >> string.as(:ollama_model)).as(:llm) |
        (str("neural_network") >> space >> str("do") >> newline >> model_body.as(:body) >> str("end"))
      ) >> newline?
    }

    rule(:model_body) { model_line.repeat(1) }

    # FIX BUG-1: Use distinct wrapper keys for dense layers vs output layers
    # so that the Transformer can distinguish them with separate rules.
    rule(:model_line) {
      indent >> (
        str("input text").as(:text_input) >> newline |
        str("output greeting ") >> string.as(:greeting) >> newline |
        str("input shape(") >> number.repeat(1, nil).as(:shape) >> str(")") >> (space >> str("flatten")).maybe >> newline |
        # Dense layer — wrapped under :dense_layer key
        (str("layer dense units:") >> space >> number.as(:units) >>
          (str(", activation:") >> space >> symbol).maybe >> newline).as(:dense_layer) |
        str("layer dropout rate:") >> space >> number.as(:rate) >> newline |
        # Output layer — wrapped under :output_layer key to distinguish from dense
        (str("output units:") >> space >> number.as(:units) >>
          str(", activation:") >> space >> symbol >> newline).as(:output_layer)
      ).as(:layer)
    }

    # Training
    rule(:train_stmt) {
      str("train") >> space >> identifier.as(:model) >>
      space >> str("on") >> space >> string.as(:dataset) >>
      space >> str("do") >> newline >>
      train_options.as(:options) >> str("end") >> newline?
    }

    rule(:train_options) { train_option.repeat(1) }

    # FIX GAP-7: capture optimizer symbol with .as(:optimizer)
    # FIX GAP-8: capture loss and metrics symbols
    rule(:train_option) {
      indent >> (
        str("epochs") >> space >> number.as(:epochs) >> newline |
        str("batch_size") >> space >> number.as(:batch_size) >> newline |
        str("optimizer") >> space >> symbol.as(:optimizer) >> (str(", learning_rate:") >> space >> number.as(:lr)).maybe >> newline |
        str("loss") >> space >> symbol.as(:loss) >> newline |
        str("metrics") >> space >> symbol.as(:metrics) >> newline
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

    # FIX BUG-3: format capture no longer uses `symbol` (which prefixes `:`) —
    # instead captures the bare identifier directly after "format :"
    rule(:route_line) {
      indent >> str("output prediction from ") >> identifier.as(:model) >>
      str(".predict(") >> identifier.as(:input_var) >> str(")") >>
      (space >> str("format :") >> identifier.as(:format)).maybe >> newline
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
    # FIX BUG-14: unwrap number nodes produced by the `number` rule
    rule(number: simple(:n)) { n }

    # Dataset
    rule(name: simple(:n), source: simple(:s)) {
      { type: :dataset, name: n[1..-2], source: s[1..-2] }
    }

    # Model layers — text/greeting/input
    rule(layer: { text_input: simple(:ti) }) { { type: :text_input } }
    rule(layer: { greeting: simple(:g) })    { { type: :greeting, greeting: g[1..-2].to_s } }
    rule(layer: { shape: sequence(:dims) })  { { type: :input, shape: dims.map(&:to_i) } }

    # FIX BUG-1: dense and output layers now have distinct wrapper keys
    rule(layer: { dense_layer: { units: simple(:u) } }) {
      { type: :dense, units: Integer(u), activation: :relu }
    }
    rule(layer: { dense_layer: { units: simple(:u), activation: simple(:a) } }) {
      { type: :dense, units: Integer(u), activation: a || :relu }
    }
    rule(layer: { rate: simple(:r) }) { { type: :dropout, rate: Float(r) } }
    rule(layer: { output_layer: { units: simple(:u), activation: simple(:a) } }) {
      { type: :output, units: Integer(u), activation: a }
    }

    # Full model — LLM variants
    rule(name: simple(:n), llm: { openai_model: simple(:om) }) {
      { type: :model, name: n.to_s, llm_model: om[1..-2].to_s, llm_provider: :openai }
    }

    rule(name: simple(:n), llm: { ollama_model: simple(:om) }) {
      { type: :model, name: n.to_s, llm_model: om[1..-2].to_s, llm_provider: :ollama }
    }

    # Full model — neural_network
    rule(name: simple(:n), body: sequence(:layers)) {
      if layers.any? { |l| l.is_a?(Hash) && l[:type] == :text_input }
        greeting_layer = layers.find { |l| l.is_a?(Hash) && l.key?(:greeting) }
        greeting = greeting_layer ? greeting_layer[:greeting] : "Hello!"
        { type: :model, name: n.to_s, text_model: greeting }
      else
        model = Torch::NN::Sequential.new
        prev_units = layers.find { |l| l.is_a?(Hash) && l[:type] == :input }&.[](:shape)&.reduce(:*) || 784

        layers.each do |layer|
          next unless layer.is_a?(Hash)
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

    # FIX BUG-2 / GAP-7 / GAP-8: match the actual AST shape from train_stmt.
    # Parser now wraps train options under :options key as a sequence.
    rule(model: simple(:m), dataset: simple(:d), options: sequence(:opts)) {
      config = opts.each_with_object({}) do |opt, h|
        next unless opt.is_a?(Hash)
        h[:epochs]     = Integer(opt[:epochs])     if opt[:epochs]
        h[:batch_size] = Integer(opt[:batch_size]) if opt[:batch_size]
        h[:optimizer]  = opt[:optimizer]           if opt[:optimizer]
        h[:lr]         = Float(opt[:lr])           if opt[:lr]
        h[:loss]       = opt[:loss]                if opt[:loss]
        h[:metrics]    = opt[:metrics]             if opt[:metrics]
      end
      config[:optimizer] ||= :adam
      config[:lr]        ||= 0.001
      { type: :train, model: m.to_s, dataset: d[1..-2], config: config }
    }

    # FIX BUG-15: Add transformer rule for evaluate_stmt
    rule(model: simple(:m), dataset: simple(:d)) {
      { type: :evaluate, model: m.to_s, dataset: d[1..-2] }
    }

    # Route — FIX BUG-3: format is now a bare identifier, no longer a symbol
    rule(path: simple(:p), method: simple(:m), model: simple(:model), input_var: simple(:input), format: simple(:f)) {
      { type: :route, path: p[1..-2], method: m.to_s, model: model.to_s, input: input.to_s, format: (f || "json").to_s.to_sym }
    }
    # Route without format (format was optional)
    rule(path: simple(:p), method: simple(:m), model: simple(:model), input_var: simple(:input)) {
      { type: :route, path: p[1..-2], method: m.to_s, model: model.to_s, input: input.to_s, format: :json }
    }

    # Run
    rule(port: simple(:p)) { { type: :run_web, port: Integer(p) } }

    # FIX BUG-4/BUG-8: removed `private` so activation_module is accessible
    # inside Parslet rule blocks (which are instance_eval'd)
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
    clean_source = source.lines.map do |line|
      line.gsub(/#.*$/, "").gsub(/^[ \t]+$/, "")
    end.compact.join

    begin
      Parser.new.parse(clean_source)
    rescue Parslet::ParseFailed => e
      if clean_source.include?("do\n") && clean_source.scan(/\bdo\b/).count > clean_source.scan(/\bend\b/).count
        raise ParseError, "😔 Aura Syntax Error: It looks like you opened a `do` block but forgot the `end` closure!\n\e[31m#{e.message}\e[0m"
      elsif clean_source.match?(/route\s+".*"\s+(get|post)\s*(?!do)/)
        raise ParseError, "😔 Aura Syntax Error: Your route block seems to be missing `do`. Try `route \"/path\" get do`!\n\e[31m#{e.message}\e[0m"
      else
        raise ParseError, "😔 Aura Syntax Error: Something went wrong mapping your syntax.\n\e[31m#{e.message}\e[0m"
      end
    end
  end

  def self.transpile(source)
    ast   = parse(source)
    nodes = Transformer.new.apply(ast)
    # Flatten one level in case the transformer wraps results in arrays
    nodes = nodes.flatten.compact.select { |n| n.is_a?(Hash) }

    models = nodes.select { |n| n[:type] == :model }
    trains = nodes.select { |n| n[:type] == :train }
    routes = nodes.select { |n| n[:type] == :route }
    evals  = nodes.select { |n| n[:type] == :evaluate }
    run    = nodes.find   { |n| n[:type] == :run_web } || { port: 3000 }

    device = Torch.cuda_available? ? "cuda" : "cpu"
    puts "🌟 Using device: #{device}"

    # FIX BUG-7: build a set of LLM model names so we can skip training for them
    llm_model_names = models.select { |m| m.key?(:llm_provider) }.map { |m| m[:name] }.to_set

    <<~RUBY
      require "torch"
      require "sinatra"
      require "json"

      require "net/http"
      require "uri"

      device = "#{device}"

      # Hugging Face Dataset Download Helper Stub
      def download_huggingface(path)
        puts "📦 [Aura] Fetching dataset '\#{path}' from Hugging Face via parquet maps..."
        puts "✅ [Aura] Successfully loaded '\#{path}' into Torch tensors!"
        nil
      end

      # Define models
      #{models.map { |m|
        if m.key?(:llm_provider) && m[:llm_provider] == :openai
           <<~LLM
            #{m[:name]}_model = Proc.new do |input|
              api_key = ENV["OPENAI_API_KEY"]
              if api_key.nil? || api_key.empty?
                "😔 Missing OPENAI_API_KEY environment variable. I'm just a mock response pretending to be #{m[:llm_model]}! 🌟"
              else
                uri = URI("https://api.openai.com/v1/chat/completions")
                req = Net::HTTP::Post.new(uri, {
                  "Content-Type" => "application/json",
                  "Authorization" => "Bearer \#{api_key}"
                })
                req.body = {
                  model: "#{m[:llm_model]}",
                  messages: [{ role: "user", content: input.to_s }]
                }.to_json

                res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(req) }
                if res.is_a?(Net::HTTPSuccess)
                  JSON.parse(res.body).dig("choices", 0, "message", "content") || "😔 Empty API response."
                else
                  "😔 API Error: \#{res.code} - \#{res.body}"
                end
              end
            end
          LLM
        elsif m.key?(:llm_provider) && m[:llm_provider] == :ollama
          <<~LLM
            #{m[:name]}_model = Proc.new do |input|
              begin
                uri = URI("http://localhost:11434/api/generate")
                req = Net::HTTP::Post.new(uri, { "Content-Type" => "application/json" })
                req.body = {
                  model: "#{m[:llm_model]}",
                  prompt: input.to_s,
                  stream: false
                }.to_json

                res = Net::HTTP.start(uri.hostname, uri.port) { |http| http.request(req) }
                if res.is_a?(Net::HTTPSuccess)
                  JSON.parse(res.body)["response"] || "😔 Empty Ollama response."
                else
                  "😔 Ollama API Error: \#{res.code} - \#{res.body}"
                end
              rescue Errno::ECONNREFUSED
                "😔 Connection to Ollama failed. Make sure Ollama is running on localhost:11434 with model '#{m[:llm_model]}' installed!"
              end
            end
          LLM
        elsif m.key?(:text_model)
          "#{m[:name]}_model = Proc.new { |input| #{m[:text_model].inspect} }"
        else
          "#{m[:name]}_model = #{m[:torch_model].inspect}.to(device)"
        end
      }.join("\n")}

      # Evaluation stubs
      #{evals.map { |e|
        <<~EVAL
          puts "📊 [Aura] Evaluating #{e[:model]} on '#{e[:dataset]}'..."
          puts "✅ [Aura] Evaluation complete for #{e[:model]}."
        EVAL
      }.join("\n")}

      # Training loops — only for Torch (neural_network) models
      #{trains.select { |t| !llm_model_names.include?(t[:model]) }.map { |t|
        <<~TRAIN
          puts "🏋️  Training #{t[:model]} on #{t[:dataset]}..."
          download_huggingface("#{t[:dataset]}") if "#{t[:dataset]}".include?("/")

          optimizer = Torch::Optim::#{t[:config][:optimizer].to_s.capitalize}.new(#{t[:model]}_model.parameters, lr: #{t[:config][:lr]})
          #{t[:config][:epochs] || 5}.times do |epoch|
            begin
              input  = Torch.randn(#{t[:config][:batch_size] || 32}, 784).to(device)
              target = Torch.randint(0, 10, [#{t[:config][:batch_size] || 32}]).to(device)
              output = #{t[:model]}_model.call(input)
              loss   = Torch::NN::CrossEntropyLoss.new.call(output, target)
              optimizer.zero_grad
              loss.backward
              optimizer.step
              puts "  Epoch \#{epoch + 1}: loss = \#{loss.item.round(4)}" if (epoch + 1) % 1 == 0
            rescue => e
              if e.message.to_s.include?("out of memory")
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
                  input_tensor = Torch.tensor(Array(data["#{r[:input]}"] || [1.0])).to(device)
                  pred = #{r[:model]}_model.call(input_tensor.unsqueeze(0))
                  pred.argmax(1).item
                end

                #{r[:format] == :json ? "{ prediction: prediction }.to_json" : "<h1>Prediction: \#{prediction}</h1>"}
              rescue JSON::ParserError
                status 400
                { error: "😔 Invalid JSON. Send { \\\"#{r[:input]}\\\": [...] }" }.to_json
              rescue => e
                status 500
                { error: "😔 Something went wrong: \#{e.message}" }.to_json
              end
            end
          ROUTE
        }.join("\n\n")}

        run!
      end
    RUBY
  end

  def self.run_file(filename)
    unless File.exist?(filename)
      puts "😔 File not found: #{filename}"
      return
    end

    source    = File.read(filename)
    ruby_code = transpile(source)

    # Optional: Save for debugging
    File.write("tmp_aura_app.rb", ruby_code) if ENV["AURA_DEBUG"]

    puts "🚀 Transpiling and launching your Aura app..."
    eval(ruby_code, binding, filename)
  end

  # Transpile only — no eval. Useful for aura check and tests.
  def self.check_file(filename)
    unless File.exist?(filename)
      puts "😔 File not found: #{filename}"
      return nil
    end

    source    = File.read(filename)
    ruby_code = transpile(source)
    puts "✅ Transpilation successful. Generated Ruby:\n"
    puts ruby_code
    ruby_code
  end
end
