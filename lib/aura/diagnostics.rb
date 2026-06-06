# frozen_string_literal: true

module Aura
  # Raised when source text cannot be parsed. Carries the line/column of the
  # failure plus a rendered snippet with a caret, so users get a real
  # diagnostic instead of a raw Parslet backtrace.
  class ParseError < StandardError
    attr_reader :line, :column

    def initialize(message, line: nil, column: nil)
      @line = line
      @column = column
      super(message)
    end
  end

  # Raised by the semantic analysis pass for problems a grammar cannot catch,
  # e.g. training/serving a model that was never defined.
  class SemanticError < StandardError; end

  # Raised when a deployment target can't host the generated app -- e.g. asking
  # to deploy a Torch model server to Vercel's serverless runtime.
  class DeployError < StandardError; end

  # Turns Parslet's internal failure cause tree into a human-friendly
  # Aura::ParseError with line/column information and a source snippet.
  module Diagnostics
    module_function

    # @param error  [Parslet::ParseFailed]
    # @param source [String] the original source text
    # @return [Aura::ParseError]
    def from_parslet(error, source)
      cause = deepest_cause(error.parse_failure_cause)
      line, column = location_for(cause)
      message = +"Parse error"
      message << " at line #{line}, column #{column}" if line
      message << ": #{cause.to_s}" if cause
      snippet = snippet_for(source, line, column)
      message << "\n\n#{snippet}" if snippet
      ParseError.new(message, line: line, column: column)
    end

    # Walk to the most specific (deepest) cause so the reported position points
    # at the actual offending token rather than the top-level rule.
    def deepest_cause(cause)
      return nil unless cause

      current = cause
      while current.respond_to?(:children) && current.children && !current.children.empty?
        # Prefer the child with the furthest source position.
        current = current.children.max_by { |c| position_of(c) || -1 }
      end
      current
    end

    def location_for(cause)
      return [nil, nil] unless cause && cause.respond_to?(:source) && cause.source

      pos = cause.respond_to?(:pos) ? cause.pos : nil
      return [nil, nil] unless pos

      line, column = cause.source.line_and_column(pos)
      [line, column]
    rescue StandardError
      [nil, nil]
    end

    def position_of(cause)
      cause.respond_to?(:pos) && cause.pos ? cause.pos.bytepos : nil
    rescue StandardError
      nil
    end

    def snippet_for(source, line, column)
      return nil unless line && column

      src_line = source.lines[line - 1]
      return nil unless src_line

      src_line = src_line.chomp
      caret = "#{' ' * (column - 1)}^"
      "  #{src_line}\n  #{caret}"
    end
  end
end
