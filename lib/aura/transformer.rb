# frozen_string_literal: true

require "parslet"

module Aura
  # Pure helper functions for assembling semantic node hashes. Kept in a module
  # (rather than Transformer instance methods) because Parslet::Transform
  # evaluates rule blocks in their own context where instance methods aren't in
  # scope -- constants like `Aura::Nodes` always are.
  module Nodes
    module_function

    def list(value)
      value.is_a?(Array) ? value : [value]
    end

    # Keep only real node hashes, discarding whitespace slices that Parslet may
    # leave in a repeated body.
    def clean(body)
      list(body).select { |x| x.is_a?(Hash) }
    end

    def model(name, body)
      layers = clean(body)
      if layers.any? { |l| %i[greeting input_text].include?(l[:type]) }
        greeting = layers.find { |l| l[:type] == :greeting }
        { type: :model, kind: :text, name: name.to_s, layers: layers,
          greeting: (greeting && greeting[:text]) || "Hello from Aura!" }
      else
        { type: :model, kind: :torch, name: name.to_s, layers: layers, torch_model: true }
      end
    end

    def transfer(name, base, body)
      { type: :model, kind: :transfer, name: name.to_s, base_model: base, layers: clean(body) }
    end

    def train(model, dataset, body)
      config = clean(body).each_with_object({}) { |opt, h| h.merge!(opt) }
      { type: :train, model: model.to_s, dataset: dataset.to_s, config: config }
    end

    def route(path, method, body)
      lines = clean(body)
      out   = lines.find { |l| l.key?(:route_model) }
      auth  = lines.find { |l| l.key?(:auth) }
      { type: :route, path: path.to_s, method: method.to_s,
        model:  out && out[:route_model],
        format: out && out[:route_format],
        auth:   auth && auth[:auth] }
    end

    def settings(body)
      clean(body).each_with_object({}) { |kv, h| h.merge!(kv) }
    end

    def dataset(name, source, path, options)
      { type: :dataset, name: name.to_s, source: source.to_s, path: path.to_s,
        options: settings(options) }
    end
  end

  # Walks the raw Parslet parse tree and rewrites it into a flat list of
  # semantic node hashes, each tagged with a :type the code generator switches
  # on. Numeric leaves are coerced to Integer/Float here (not String) so node
  # values are directly usable.
  class Transformer < Parslet::Transform
    # ---- leaves --------------------------------------------------------------
    rule(str: simple(:s))    { s.to_s }
    rule(sym: simple(:s))    { s.to_s.to_sym }
    rule(bool: simple(:b))   { b.to_s == "true" }
    rule(number: simple(:n)) { (x = n.to_s).include?(".") ? x.to_f : x.to_i }

    # ---- model body lines ----------------------------------------------------
    rule(input_shape: subtree(:s)) { { type: :input, shape: Aura::Nodes.list(s) } }
    rule(input_shape: subtree(:s), input_transforms: subtree(:t)) { { type: :input, shape: Aura::Nodes.list(s), transforms: Aura::Nodes.clean(t) } }
    rule(tf_key: simple(:k), tf_value: simple(:v)) { { transform: k.to_s.to_sym, value: v } }
    rule(tf_key: simple(:k)) { { transform: k.to_s.to_sym } }
    rule(input_text: simple(:_x))  { { type: :input_text } }
    rule(conv_filters: simple(:f), conv_kernel: simple(:k)) { { type: :conv2d, filters: f.to_i, kernel: k.to_i } }
    rule(pool_size: simple(:s))    { { type: :maxpool2d, size: s.to_i } }
    rule(batchnorm: simple(:_x))   { { type: :batchnorm } }
    rule(flatten: simple(:_x))     { { type: :flatten } }
    rule(dense_units: simple(:u), dense_activation: simple(:a)) { { type: :dense, units: u.to_i, activation: a } }
    rule(dense_units: simple(:u))  { { type: :dense, units: u.to_i, activation: :linear } }
    rule(dropout_rate: simple(:r)) { { type: :dropout, rate: r.to_f } }
    rule(out_units: simple(:u), out_activation: simple(:a)) { { type: :output, units: u.to_i, activation: a } }
    rule(greeting: simple(:g))     { { type: :greeting, text: g.to_s } }
    rule(save_path: simple(:p))    { { type: :save_weights, path: p.to_s } }
    rule(load_path: simple(:p))    { { type: :load_weights, path: p.to_s } }
    rule(freeze_until: simple(:l))  { { type: :freeze, until: l } }
    rule(unfreeze_all: simple(:_x)) { { type: :unfreeze_all } }

    # ---- route body lines ----------------------------------------------------
    rule(route_model: simple(:m), route_input: simple(:i), route_format: simple(:f)) { { route_model: m.to_s, route_format: f } }
    rule(route_model: simple(:m), route_input: simple(:i)) { { route_model: m.to_s, route_format: nil } }
    rule(auth: simple(:a)) { { auth: a } }

    # ---- key/value lines (env + dataset options) -----------------------------
    rule(env_key: simple(:k), env_value: simple(:v)) { { k.to_s.to_sym => v } }
    rule(opt_key: simple(:k), opt_value: simple(:v)) { { k.to_s.to_sym => v } }

    # ---- statements ----------------------------------------------------------
    rule(ds_name: simple(:n), ds_source: simple(:s), ds_path: simple(:p), ds_options: subtree(:o)) { Aura::Nodes.dataset(n, s, p, o) }
    rule(ds_name: simple(:n), ds_source: simple(:s), ds_path: simple(:p)) { Aura::Nodes.dataset(n, s, p, []) }

    rule(env_name: simple(:n), env_body: subtree(:b)) { { type: :environment, name: n.to_s, settings: Aura::Nodes.settings(b) } }

    rule(model_name: simple(:n), nn_body: subtree(:b)) { Aura::Nodes.model(n, b) }
    rule(model_name: simple(:n), provider: simple(:pr), model_id: simple(:mid)) { { type: :model, kind: :llm, name: n.to_s, provider: pr.to_s.to_sym, model_id: mid.to_s } }
    rule(model_name: simple(:n), base_model: simple(:bm)) { { type: :model, kind: :transfer, name: n.to_s, base_model: bm, layers: [] } }
    rule(model_name: simple(:n), base_model: simple(:bm), nn_body: subtree(:b)) { Aura::Nodes.transfer(n, bm, b) }

    rule(tr_model: simple(:m), tr_dataset: simple(:d), tr_body: subtree(:b)) { Aura::Nodes.train(m, d, b) }

    rule(ev_model: simple(:m), ev_dataset: simple(:d)) { { type: :evaluate, model: m.to_s, dataset: d.to_s } }

    rule(rt_path: simple(:p), rt_method: simple(:m), rt_body: subtree(:b)) { Aura::Nodes.route(p, m, b) }

    rule(port: simple(:p)) { { type: :run_web, port: p.to_i } }
  end
end
