# lib/aura.rb
require "parslet"
require "sinatra/base"
require "json"
require "logger"
require "set"
require "fileutils"

# Load real Torch
begin
  require "torch"
rescue LoadError
end

module Aura
  class ParseError < StandardError; end

  class Parser < Parslet::Parser
    rule(:space)      { str(" ").repeat(1) }
    rule(:space?)     { space.maybe }
    rule(:newline)    { (str("\n") | str("\r\n")).repeat(1) }
    rule(:newline?)   { newline.maybe }
    rule(:indent)     { str("  ").repeat(1) }

    rule(:string)     { str('"') >> (str('"').absent? >> any).repeat.as(:str) >> str('"') }
    rule(:identifier) { match('[a-zA-Z_]') >> match('[a-zA-Z0-9_]').repeat }
    rule(:number)     { (match('[0-9]').repeat(1) >> (str('.') >> match('[0-9]').repeat(1)).maybe).as(:number) }
    rule(:symbol)     { str(":") >> identifier.as(:sym) }

    rule(:dataset_stmt) {
      str("dataset") >> space >> string.as(:name) >>
      space >> str("from") >> space >> identifier.as(:source) >> space >> string.as(:path) >>
      (space >> str("do") >> newline >> dataset_options.as(:options) >> str("end")).maybe >>
      newline?
    }
    rule(:dataset_options) { dataset_option.repeat(1) }
    rule(:dataset_option) { indent >> identifier.as(:key) >> space >> (string | number | symbol).as(:value) >> newline }

    rule(:env_stmt) {
      str("environment") >> space >> identifier.as(:name) >> space >> str("do") >> newline >>
      env_body.as(:config) >> str("end") >> newline?
    }
    rule(:env_body) { env_line.repeat(1) }
    rule(:env_line) { indent >> identifier.as(:key) >> space >> (string | number | symbol).as(:value) >> newline }

    rule(:model_stmt) {
      str("model") >> space >> identifier.as(:name) >> space >> (
        (str("from") >> space >> identifier.as(:provider) >> space >> string.as(:model_id)).as(:llm) |
        (str("transfer from") >> space >> symbol.as(:base_model)).as(:transfer) |
        (str("neural_network") >> space >> str("do") >> newline >> model_body.as(:body) >> str("end"))
      ) >> newline?
    }
    rule(:model_body) { model_line.repeat(1) }
    rule(:model_line) {
      indent >> (
        str("input text").as(:text_input) |
        (str("input shape(") >> (number >> (str(", ") >> number).repeat).as(:shape) >> str(")") >> 
          (space >> str("do") >> newline >> transforms.as(:transforms) >> str("end")).maybe
        ).as(:input_stmt) |
        str("layer dense units:") >> space >> number.as(:units) >> (str(", activation:") >> space >> symbol.as(:activation)).maybe |
        str("layer conv2d filters:") >> space >> number.as(:filters) >> str(", kernel:") >> space >> number.as(:kernel) >> (str(", stride:") >> space >> number.as(:stride)).maybe |
        str("layer maxpool2d size:") >> space >> number.as(:size) |
        str("layer dropout rate:") >> space >> number.as(:rate) |
        str("layer batchnorm").as(:batchnorm) |
        str("layer flatten").as(:flatten_layer) |
        str("output units:") >> space >> number.as(:units) >> str(", activation:") >> space >> symbol.as(:activation) |
        str("freeze until ") >> identifier.as(:layer_name) |
        str("unfreeze all").as(:unfreeze_all) |
        (str("load weights from ") >> string.as(:weights_path)).as(:load_weights) |
        (str("save weights to ") >> string.as(:weights_path)).as(:save_weights)
      ).as(:layer) >> newline
    }

    rule(:transforms) { transform.repeat(1) }
    rule(:transform) {
      indent >> indent >> identifier.as(:name) >> (space >> (number | string).as(:arg)).maybe >> newline
    }

    rule(:train_stmt) {
      str("train") >> space >> identifier.as(:model) >> space >> str("on") >> space >> string.as(:dataset) >>
      space >> str("do") >> newline >> train_options.as(:options) >> str("end") >> newline?
    }
    rule(:train_options) { train_option.repeat(1) }
    rule(:train_option) {
      indent >> (
        str("epochs") >> space >> number.as(:epochs) |
        str("batch_size") >> space >> number.as(:batch_size) |
        str("optimizer") >> space >> symbol.as(:optimizer) >> (str(", learning_rate:") >> space >> number.as(:lr)).maybe |
        str("scheduler") >> space >> symbol.as(:scheduler_type) |
        str("loss") >> space >> symbol.as(:loss) |
        str("metrics") >> space >> symbol.as(:metrics) |
        str("save_every") >> space >> number.as(:save_every)
      ) >> newline
    }

    rule(:evaluate_stmt) {
      str("evaluate") >> space >> identifier.as(:model) >> space >> str("on") >> space >> string.as(:dataset) >> newline?
    }

    rule(:route_stmt) {
      str("route") >> space >> string.as(:path) >> space >> (str("get") | str("post")).as(:method) >> space >> str("do") >> newline >>
      route_body.as(:body) >> str("end") >> newline?
    }
    rule(:route_body) { route_line.repeat(1) }
    rule(:route_line) {
      indent >> (
        str("authenticate with ") >> symbol.as(:auth_method) |
        str("output prediction from ") >> identifier.as(:model) >> str(".predict(") >> identifier.as(:input_var) >> str(")") >>
        (space >> str("format :") >> identifier.as(:format)).maybe |
        str("render ") >> string.as(:template) |
        str("set ") >> identifier.as(:var) >> str(" = ") >> identifier.as(:val)
      ).as(:line) >> newline
    }

    rule(:run_stmt) { str("run web on port:") >> space >> number.as(:port) >> newline? }
    
    rule(:statement) { (dataset_stmt | env_stmt | model_stmt | train_stmt | evaluate_stmt | route_stmt | run_stmt | newline) }
    rule(:program) { statement.repeat }
    root :program
  end

  class Transformer < Parslet::Transform
    rule(str: simple(:s)) { s.to_s }
    rule(sym: simple(:s)) { s.to_s.to_sym }
    rule(number: simple(:n)) { n.to_s.include?('.') ? n.to_f : n.to_i }

    rule(name: simple(:n), source: simple(:s), path: simple(:p), options: subtree(:o)) { { type: :dataset, name: n.to_s, options: o } }
    rule(name: simple(:n), source: simple(:s), path: simple(:p)) { { type: :dataset, name: n.to_s, options: [] } }
    rule(name: simple(:n), config: subtree(:c)) { { type: :env, name: n.to_s, config: c } }
    
    rule(name: simple(:n), transfer: { base_model: simple(:bm) }) { { type: :model, name: n.to_s, transfer: bm, torch_model: true } }
    rule(name: simple(:n), llm: { provider: simple(:p), model_id: simple(:mid) }) { { type: :model, name: n.to_s, llm_provider: p.to_s, model_id: mid.to_s } }
    rule(name: simple(:n), body: subtree(:l)) { { type: :model, name: n.to_s, layers: l, torch_model: true } }
    
    rule(layer: { input_stmt: { shape: subtree(:s), transforms: subtree(:t) } }) { { type: :input, shape: Array(s).map(&:to_i), transforms: t } }
    rule(layer: { input_stmt: { shape: subtree(:s) } }) { { type: :input, shape: Array(s).map(&:to_i), transforms: [] } }
    
    rule(layer: { units: simple(:u), activation: simple(:a) }) { { type: :dense, units: u.to_i, activation: a } }
    rule(layer: { units: simple(:u) }) { { type: :dense, units: u.to_i, activation: :relu } }
    rule(layer: { filters: simple(:f), kernel: simple(:k) }) { { type: :conv2d, filters: f.to_i, kernel: k.to_i } }
    rule(layer: { size: simple(:s) }) { { type: :maxpool2d, size: s.to_i } }
    rule(layer: { rate: simple(:r) }) { { type: :dropout, rate: r.to_f } }
    rule(layer: { batchnorm: simple(:_) }) { { type: :batchnorm } }
    rule(layer: { flatten_layer: simple(:_) }) { { type: :flatten } }
    rule(layer: { unfreeze_all: simple(:_) }) { { type: :unfreeze_all } }
    rule(layer: { layer_name: simple(:n) }) { { type: :freeze_until, name: n.to_s } }
    rule(layer: { load_weights: { weights_path: simple(:p) } }) { { type: :load_weights, path: p.to_s } }
    rule(layer: { save_weights: { weights_path: simple(:p) } }) { { type: :save_weights, path: p.to_s } }

    rule(model: simple(:m), dataset: simple(:d), options: subtree(:o)) {
      config = {}
      o.each { |item| config.merge!(item) if item.is_a?(Hash) }
      { type: :train, model: m.to_s, dataset: d.to_s, config: config }
    }
    
    rule(model: simple(:m), dataset: simple(:d)) {
      { type: :evaluate, model: m.to_s, dataset: d.to_s }
    }
    
    rule(path: simple(:p), method: simple(:m), body: subtree(:b)) { 
      fmt = b.find { |line| line[:line][:format] }
      format_sym = fmt ? fmt[:line][:format].to_s.to_sym : nil
      { type: :route, path: p.to_s, method: m.to_s, body: b, format: format_sym } 
    }
    rule(port: simple(:p)) { { type: :run_web, port: p.to_i } }
  end

  def self.parse(source)
    Parser.new.parse(source.gsub(/#.*$/, ""))
  end

  def self.transpile(source)
    ast = parse(source)
    nodes = Transformer.new.apply(ast).flatten.compact
    
    output = ["# Aura v1.2.0 Advanced (Restored)", "require 'torch'", "require 'sinatra/base'", "require 'json'", "require 'logger'", "require 'net/http'", "require 'uri'", "DEVICE = Torch.cuda_available? ? 'cuda' : 'cpu'"]
    
    routes = nodes.select { |n| n[:type] == :route }

    has_web = nodes.any? { |n| n[:type] == :run_web } || routes.any?

    nodes.each do |n|
      case n[:type]
      when :env
        output << "class AuraConfig"
        output << "  def self.load"
        output << "    {"
        n[:config].each do |item|
          k = item[:key] || item["key"]
          v = item[:value] || item["value"]
          val_str = v.is_a?(String) ? "\"#{v}\"" : v
          output << "      #{k}: #{val_str},"
        end
        output << "    }"
        output << "  end"
        output << "end"
      when :model
        if n[:llm_provider] == "openai"
          output << "class #{n[:name].capitalize}Model"
          output << "  def predict(msg)"
          output << "    api_key = ENV[\"OPENAI_API_KEY\"]"
          output << "    uri = URI('https://api.openai.com/v1/chat/completions')"
          output << "    req = Net::HTTP::Post.new(uri, 'Content-Type' => 'application/json', 'Authorization' => \"Bearer \#{api_key}\")"
          output << "    req.body = { model: \"#{n[:model_id]}\", messages: [{ role: 'user', content: msg }] }.to_json"
          output << "    res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(req) }"
          output << "    JSON.parse(res.body).dig('choices', 0, 'message', 'content')"
          output << "  end"
          output << "end"
          output << "#{n[:name]}_model = #{n[:name].capitalize}Model.new"
        elsif n[:llm_provider] == "ollama"
          output << "class #{n[:name].capitalize}Model"
          output << "  def predict(msg)"
          output << "    uri = URI('http://localhost:11434/api/generate')"
          output << "    req = Net::HTTP::Post.new(uri, 'Content-Type' => 'application/json')"
          output << "    req.body = { model: \"#{n[:model_id]}\", prompt: msg, stream: false }.to_json"
          output << "    res = Net::HTTP.start(uri.hostname, uri.port) { |http| http.request(req) }"
          output << "    JSON.parse(res.body)['response']"
          output << "  end"
          output << "end"
          output << "#{n[:name]}_model = #{n[:name].capitalize}Model.new"
        elsif n[:transfer]
          output << "class #{n[:name].capitalize}Model < Torch::NN::Module"
          output << "  def initialize; super; @base = Torchvision::Models.#{n[:transfer]}(pretrained: true); end"
          output << "  def forward(x); @base.call(x); end"
          output << "end"
          output << "#{n[:name]}_model = #{n[:name].capitalize}Model.new.to(DEVICE)"
        else
          output << "class #{n[:name].capitalize}Model < Torch::NN::Module"
          output << "  def initialize"
          output << "    super"
          channels = 1
          n[:layers]&.each_with_index do |l, i|
            if l[:type] == :conv2d
              output << "    @layer#{i} = Torch::NN::Conv2d.new(#{channels}, #{l[:filters]}, #{l[:kernel]})"
              channels = l[:filters]
            end
          end
          output << "  end"
          output << "  def forward(x)"
          n[:layers]&.each_with_index do |l, i|
            if l[:type] == :conv2d
              output << "    x = @layer#{i}.call(x)"
            elsif l[:type] == :flatten
              output << "    x = x.view(x.size(0), -1)"
            end
          end
          output << "    x"
          output << "  end"
          output << "end"
          output << "#{n[:name]}_model = #{n[:name].capitalize}Model.new.to(DEVICE)"
        end
      when :train
        output << "# Advanced Training Loop"
        output << "optimizer = Torch::Optim::#{n[:config][:optimizer] || 'Adam'}.new(#{n[:model]}_model.parameters)"
        if n[:config][:scheduler_type]
           output << "scheduler = Torch::Optim::LRScheduler::#{n[:config][:scheduler_type]}.new(optimizer)"
        end
        epochs = n[:config][:epochs] || 1
        output << "#{epochs}.times do |epoch|"
        output << "  #{n[:model]}_model.train"
        output << "end"
      end
    end

    if has_web
      port_node = nodes.find { |n| n[:type] == :run_web }
      port = port_node ? port_node[:port] : 3000
      output << "class App < Sinatra::Base"
      output << "  set :port, #{port}"
      routes.each do |r|
        output << "  #{r[:method]} '#{r[:path]}' do"
        r[:body]&.each do |line|
          if line[:line] && line[:line][:model]
            output << "    #{line[:line][:model]}_model.call(Torch.tensor(input))"
          end
        end
        output << "  end"
      end
      output << "end"
      output << "App.run!"
    end
    output.join("\n")
  end

  def self.run_file(f); eval(transpile(File.read(f))); end
  
  def self.build_docker(filename)
    dockerfile = <<~DOCKER
      FROM ruby:3.3
      RUN apt-get update && apt-get install -y libtorch-dev
      WORKDIR /app
      COPY Gemfile* ./
      RUN bundle install
      COPY . .
      EXPOSE 8080
      CMD ["aura", "run", "#{filename}"]
    DOCKER
    File.write("Dockerfile", dockerfile)
    puts "🐳 Dockerfile generated for #{filename}"
  end
end
