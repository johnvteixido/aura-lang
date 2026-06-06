# frozen_string_literal: true

module Aura
  # A tiny indentation-aware code builder. Replaces ad-hoc string
  # concatenation in the code generator so emitted Ruby is consistently
  # indented and blocks are hard to leave unbalanced.
  #
  #   e = Emitter.new
  #   e.line "x = 1"
  #   e.block("def forward(x)") { e.line "x" }
  #   e.to_s
  #
  class Emitter
    INDENT = "  "

    def initialize
      @lines = []
      @depth = 0
    end

    # Append a line (or several "\n"-separated lines) at the current indent.
    def line(text = "")
      text.to_s.split("\n", -1).each do |raw|
        @lines << (raw.empty? ? "" : "#{INDENT * @depth}#{raw}")
      end
      self
    end

    # Append a blank line.
    def blank
      @lines << ""
      self
    end

    # Append a comment line.
    def comment(text)
      line("# #{text}")
    end

    # Emit `header` then an indented body produced by the block, then `footer`
    # (defaults to `end`). Used for classes, methods, and Ruby blocks.
    def block(header, footer = "end")
      line(header)
      indent { yield self }
      line(footer)
      self
    end

    # Increase indentation for the duration of the block.
    def indent
      @depth += 1
      yield self
    ensure
      @depth -= 1
    end

    def to_s
      "#{@lines.join("\n")}\n"
    end
  end
end
