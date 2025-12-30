require "parslet"
require "json"
require "sinatra/base"
require "torch"

module Aura
  class Parser < Parslet::Parser
    # Minimal beautiful grammar — Ruby-style

    rule(:space)      { str(" ").repeat(1) }
    rule(:space?)     { space.maybe }
    rule(:newline)    { str("\n") | str("\r\n") }
    rule(:indent)     { space.repeat(1) }

    rule(:identifier) { match('[a-zA-Z_]').repeat(1) }
    rule(:string)     { str('"') >> (str('"').absent >> any).repeat >> str('"') }
    rule(:number)     { match('[0-9]').repeat(1).as(:int) }
    rule(:symbol)     { str(":") >> identifier.as(:symbol) }

    rule(:dataset) {
      str("dataset") >> space >> string.as(:name) >> space >>
      str("from") >> space >> str("huggingface") >> space >> string.as(:hf_name) >>
      (space >> str("split") >> space >> identifier.as(:split1) >>
       (str(",") >> space >> identifier.as(:split2)).maybe).maybe >> newline
    }

    rule(:model_block) {
      str("model") >> space >> identifier.as(:name) >> space >> str("neural_network") >> space >> str("do") >> newline >>
      (indent >> model_line).repeat >> str("end")
    }

    rule(:model_line) {
      indent >> (
        str("input shape(") >> number.repeat(1, nil).as(:shape) >> str(")") >> (space >> str("flatten")).maybe >> newline |
        str("layer dense units:") >> space >> number.as(:units) >> (str(",") >> space >> str("activation:") >> space >> symbol).maybe >> newline |
        str("layer dropout rate:") >> space >> number.as(:float) >> newline |
        str("output units:") >> space >> number.as(:units) >> str(",") >> space >> str("activation:") >> space >> symbol >> newline
      )
    }

    rule(:statement) { dataset | model_block | newline }
    rule(:program)   { statement.repeat }

    root(:program)
  end

  def self.parse(source)
    Parser.new.parse(source)
  rescue Parslet::ParseFailed => e
    puts "😔 Parse error: #{e.message}"
    puts e.cause.ascii_tree
    exit 1
  end

  def self.run_file(filename)
    source = File.read(filename)
    ast = parse(source)
    puts "🎉 Parsed successfully!"
    pp ast # Pretty-print AST for now
    # Next step: Transpiler will go here
  end
end
