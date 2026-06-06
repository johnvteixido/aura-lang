# frozen_string_literal: true

# Aura -- the declarative AI web framework. This file is the loader and public
# API surface; the compiler pipeline lives in the focused modules under
# lib/aura/ (parser -> transformer -> analyzer -> codegen).

require "json"
require "fileutils"

# Torch is only needed to *run* generated models. Transpilation, `check`, and
# `build` all work without it, so a missing install is not fatal here.
begin
  require "torch"
rescue LoadError
  nil
end

require_relative "aura/version"
require_relative "aura/diagnostics"
require_relative "aura/emitter"
require_relative "aura/parser"
require_relative "aura/transformer"
require_relative "aura/analyzer"
require_relative "aura/codegen"
require_relative "aura/docker"

module Aura
  # A small, fully-parseable starter app used by `aura init` and the
  # "file not found" recovery path in `aura run`. Kept here so the CLI and the
  # test-suite share a single source of truth.
  STARTER_TEMPLATE = <<~AURA
    environment production do
      device :cpu
      log_level :info
    end

    model greeter neural_network do
      input text
      output greeting "Hello from Aura!"
    end

    route "/hello" get do
      output prediction from greeter.predict(input) format :json
    end

    run web on port: 3000
  AURA

  module_function

  # Strip full-line `#` comments before parsing. The comment text is removed but
  # the newline is kept, so line numbers stay accurate for diagnostics. Also
  # normalizes the source to UTF-8 (examples may contain emoji, etc.).
  def preprocess(source)
    source.to_s.dup.force_encoding("UTF-8").gsub(/^[ \t]*#.*$/, "")
  end

  # Parse source into the raw Parslet tree, converting a Parslet failure into a
  # friendly Aura::ParseError with line/column. Returns the raw tree so callers
  # may run the Transformer themselves.
  def parse(source)
    clean = preprocess(source)
    Parser.new.parse(clean)
  rescue Parslet::ParseFailed => e
    raise Diagnostics.from_parslet(e, clean)
  end

  # Full front-end: parse -> transform -> semantic analysis. Returns the flat
  # list of semantic node hashes.
  def to_nodes(source)
    tree  = parse(source)
    nodes = Transformer.new.apply(tree)
    nodes = nodes.is_a?(Array) ? nodes : [nodes]
    nodes = nodes.flatten.compact.select { |n| n.is_a?(Hash) }
    Analyzer.analyze(nodes)
  end

  # Transpile Aura source to a Ruby program (String).
  def transpile(source)
    CodeGen.generate(to_nodes(source))
  end

  # Transpile and execute a .aura file. Generated code uses classic Sinatra,
  # which boots the server at exit.
  def run_file(filename)
    eval(transpile(File.read(filename)), TOPLEVEL_BINDING, filename) # rubocop:disable Security/Eval
  end

  # Generate Docker deployment assets for a .aura file (backs `aura deploy`).
  def build_docker(filename)
    Docker.build(filename)
  end
end
