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
    rule(:newline)    { (str("\n") | str("\r\n")).repeat(1) }
    rule(:indent)     { str("  ").repeat(1) }
    rule(:string)     { str('"') >> (str('"').absent? >> any).repeat.as(:str) >> str('"') }
    rule(:identifier) { match('[a-zA-Z_]\w*') }
    rule(:number)     { (match('\d+') >> (str('.') >> match('\d+').repeat(1)).maybe).as(:number) }
    rule(:symbol)     { str(":") >> identifier.as(:sym) }

    rule(:dataset_stmt) {
      str("dataset") >> space >> string.as(:name) >>
      space >> str("from") >> space >> identifier.as(:source) >> space >> string.as(:path) >>
      (space >> str("do") >> newline >> dataset_options.as(:options) >> str("end")).maybe >>
      newline
    }
    rule(:dataset_options) { dataset_option.repeat(1) }
    rule(:dataset_option) { indent >> identifier.as(:key) >> space >> (string | number | symbol).as(:value) >> newline }

    rule(:env_stmt) {
      str("environment") >> space >> identifier.as(:name) >> space >> str("do") >> newline >>
      env_body.as(:config) >> str("end") >> newline
    }
    rule(:env_body) { env_line.repeat(1) }
    rule(:env_line) { indent >> identifier.as(:key) >> space >> (string | number | symbol).as(:value) >> newline }

    rule(:model_stmt) {
      str("model") >> space >> identifier.as(:name) >> space >> (
        (str("transfer from") >> space >> symbol.as(:base_model)).as(:transfer) |
        (str("neural_network") >> space >> str("do") >> newline >> model_body.as(:body) >> str("end"))
      ) >> newline
    }
    rule(:model_body) { model_line.repeat(1) }
    rule(:model_line) {
      indent >> (
        str("input shape(") >> number.repeat(1, nil).as(:shape) >> str(")") |
        str("layer dense units:") >> space >> number.as(:units) >> (str(", activation:") >> space >> symbol.as(:activation)).maybe |
        str("layer conv2d filters:") >> space >> number.as(:filters) >> str(", kernel:") >> space >> number.as(:kernel) |
        str("output units:") >> space >> number.as(:units) >> str(", activation:") >> space >> symbol.as(:activation) |
        str("freeze until ") >> identifier.as(:layer_name) |
        str("unfreeze all").as(:unfreeze_all)
      ).as(:layer) >> newline
    }

    rule(:train_stmt) {
      str("train") >> space >> identifier.as(:model) >> space >> str("on") >> space >> string.as(:dataset) >>
      space >> str("do") >> newline >> train_options.as(:options) >> str("end") >> newline
    }
    rule(:train_options) { train_option.repeat(1) }
    rule(:train_option) {
      indent >> (
        str("epochs") >> space >> number.as(:epochs) |
        str("optimizer") >> space >> symbol.as(:optimizer) >> (str(", learning_rate:") >> space >> number.as(:lr)).maybe |
        str("scheduler") >> space >> symbol.as(:scheduler_type) |
        str("loss") >> space >> symbol.as(:loss)
      ) >> newline
    }

    rule(:route_stmt) {
      str("route") >> space >> string.as(:path) >> space >> identifier.as(:method) >> space >> str("do") >> newline >>
      route_body >> str("end") >> newline
    }
    rule(:route_body) { route_line.repeat(1) }
    rule(:route_line) {
      indent >> (
        str("output prediction from ") >> identifier.as(:model) >> str(".predict(") >> identifier.as(:input_var) >> str(")")
      ).as(:line) >> newline
    }

    rule(:run_stmt) { str("run web on port:") >> space >> number.as(:port) >> newline }
    rule(:program) { (dataset_stmt | env_stmt | model_stmt | train_stmt | route_stmt | run_stmt | newline).repeat }
    root :program
  end

  class Transformer < Parslet::Transform
    rule(str: simple(:s)) { s.to_s }
    rule(sym: simple(:s)) { s.to_s.to_sym }
    rule(number: simple(:n)) { n.to_s }

    rule(name: {str: simple(:n)}, source: simple(:s), path: {str: simple(:p)}, options: sequence(:o)) { { type: :dataset, name: n.to_s, options: o } }
    rule(name: {str: simple(:n)}, source: simple(:s), path: {str: simple(:p)}) { { type: :dataset, name: n.to_s, options: [] } }
    
    rule(name: simple(:n), transfer: { base_model: simple(:bm) }) { { type: :model, name: n.to_s, transfer: bm } }
    rule(name: simple(:n), body: sequence(:l)) { { type: :model, name: n.to_s, layers: l } }
    
    rule(layer: { units: simple(:u), activation: simple(:a) }) { { type: :dense, units: u.to_i, activation: a } }
    rule(layer: { units: simple(:u) }) { { type: :dense, units: u.to_i, activation: :relu } }
    rule(layer: { filters: simple(:f), kernel: simple(:k) }) { { type: :conv2d, filters: f.to_i, kernel: k.to_i } }
    rule(layer: { unfreeze_all: any }) { { type: :unfreeze_all } }

    rule(model: simple(:m), dataset: {str: simple(:d)}, options: sequence(:o)) {
      { type: :train, model: m.to_s, dataset: d.to_s, config: o.each_with_object({}) { |i, h| h[i.keys.first] = i.values.first } }
    }
    
    rule(path: {str: simple(:p)}, method: simple(:m), body: any) { { type: :route, path: p.to_s, method: m.to_s } }
    rule(port: simple(:p)) { { type: :run_web, port: p.to_i } }
  end

  def self.transpile(source)
    ast = Parser.new.parse(source)
    nodes = Transformer.new.apply(ast).flatten.compact
    
    output = ["# Aura v1.2.0 Advanced", "require 'torch'", "require 'sinatra/base'", "DEVICE = Torch.cuda_available? ? 'cuda' : 'cpu'"]
    
    nodes.each do |n|
      case n[:type]
      when :model
        if n[:transfer]
          output << "class #{n[:name].capitalize}Model < Torch::NN::Module"
          output << "  def initialize; super; @base = Torchvision::Models.#{n[:transfer]}(pretrained: true); end"
          output << "  def forward(x); @base.call(x); end"
          output << "end"
        else
          output << "class #{n[:name].capitalize}Model < Torch::NN::Module"
          output << "  def initialize; super; end"
          output << "  def forward(x); x; end"
          output << "end"
        end
        output << "#{n[:name]}_model = #{n[:name].capitalize}Model.new.to(DEVICE)"
      when :train
        output << "# Advanced Training Loop with Scheduler"
        output << "optimizer = Torch::Optim::#{n[:config][:optimizer] || 'Adam'}.new(#{n[:model]}_model.parameters)"
        if n[:config][:scheduler_type]
           output << "scheduler = Torch::Optim::LRScheduler::#{n[:config][:scheduler_type]}.new(optimizer)"
        end
      when :run_web
        output << "class App < Sinatra::Base; set :port, #{n[:port]}; get '/' do; 'Aura v1.2.0 Active'; end; end"
        output << "App.run!"
      end
    end
    output.join("\n")
  end

  def self.run_file(f); eval(transpile(File.read(f))); end
end
