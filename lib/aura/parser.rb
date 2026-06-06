# frozen_string_literal: true

require "parslet"

module Aura
  # PEG grammar for the Aura DSL, built on Parslet. The grammar is whitespace-
  # and blank-line tolerant; full-line `#` comments are stripped (and replaced
  # by blank lines, preserving line numbers) before parsing -- see
  # Aura.preprocess in lib/aura.rb.
  class Parser < Parslet::Parser
    # ---- lexical -------------------------------------------------------------
    rule(:sp)  { match('[ \t]').repeat }
    rule(:sp1) { match('[ \t]').repeat(1) }
    rule(:nl)  { str("\r\n") | str("\n") | str("\r") }
    # End of a content line: trailing spaces then a newline (or end of input).
    rule(:eol) { sp >> (nl | any.absent?) }
    # Zero or more whitespace-only lines.
    rule(:blank_lines) { (sp >> nl).repeat }

    rule(:identifier) { match('[a-zA-Z_]') >> match('[a-zA-Z0-9_]').repeat }
    rule(:string)  { str('"') >> (str('"').absent? >> any).repeat.as(:str) >> str('"') }
    rule(:number)  { (match('[0-9]').repeat(1) >> (str(".") >> match('[0-9]').repeat(1)).maybe).as(:number) }
    rule(:symbol)  { str(":") >> identifier.as(:sym) }
    rule(:boolean) { (str("true") | str("false")).as(:bool) }
    rule(:value)   { string | number | boolean | symbol }

    # Comma separator that tolerates surrounding spaces.
    rule(:comma) { sp >> str(",") >> sp }

    # ---- helpers -------------------------------------------------------------
    # A `do ... end` block whose body is zero or more `line_atom`s (blank lines
    # between them are skipped). The collected lines are captured under `key`.
    def block_body(line_atom, key)
      str("do") >> eol >>
        (blank_lines >> line_atom).repeat.as(key) >>
        blank_lines >> sp >> str("end")
    end

    # ---- program -------------------------------------------------------------
    rule(:program) { blank_lines >> (statement >> blank_lines).repeat >> sp }
    rule(:statement) do
      dataset_stmt | env_stmt | model_stmt | train_stmt |
        evaluate_stmt | route_stmt | run_stmt
    end
    root :program

    # ---- dataset -------------------------------------------------------------
    rule(:dataset_stmt) do
      str("dataset") >> sp1 >> string.as(:ds_name) >> sp1 >>
        str("from") >> sp1 >> identifier.as(:ds_source) >> sp1 >> string.as(:ds_path) >>
        (sp1 >> block_body(dataset_option, :ds_options)).maybe >> eol
    end
    rule(:dataset_option) do
      sp >> identifier.as(:opt_key) >> sp1 >> value.as(:opt_value) >> eol
    end

    # ---- environment ---------------------------------------------------------
    rule(:env_stmt) do
      str("environment") >> sp1 >> identifier.as(:env_name) >> sp1 >>
        block_body(env_line, :env_body) >> eol
    end
    rule(:env_line) do
      sp >> identifier.as(:env_key) >> sp1 >> value.as(:env_value) >> eol
    end

    # ---- model ---------------------------------------------------------------
    rule(:model_stmt) do
      str("model") >> sp1 >> identifier.as(:model_name) >> sp1 >> (
        (str("neural_network") >> sp1 >> block_body(model_line, :nn_body)) |
        (str("from") >> sp1 >> identifier.as(:provider) >> sp1 >> string.as(:model_id)) |
        (str("transfer") >> sp1 >> str("from") >> sp1 >> symbol.as(:base_model) >>
          (sp1 >> block_body(model_line, :nn_body)).maybe)
      ) >> eol
    end

    rule(:model_line) do
      sp >> (
        m_input_shape | m_input_text | m_conv | m_maxpool | m_batchnorm |
        m_flatten | m_dense | m_dropout | m_output | m_greeting |
        m_load | m_save | m_freeze | m_unfreeze
      ) >> eol
    end

    rule(:m_input_shape) do
      str("input") >> sp1 >> str("shape(") >> sp >>
        (number >> comma.maybe).repeat(1).as(:input_shape) >> sp >> str(")") >>
        (sp1 >> block_body(input_transform, :input_transforms)).maybe
    end
    # A preprocessing directive inside an `input shape(...) do ... end` block,
    # e.g. `resize 28` or `to_tensor`. The `end`-line guard stops the value-less
    # form from swallowing the block terminator.
    rule(:input_transform) do
      sp >> (str("end") >> eol).absent? >> identifier.as(:tf_key) >>
        (sp1 >> value.as(:tf_value)).maybe >> eol
    end
    rule(:m_input_text) { str("input") >> sp1 >> str("text").as(:input_text) }
    rule(:m_conv) do
      str("layer") >> sp1 >> str("conv2d") >> sp1 >>
        str("filters:") >> sp1 >> number.as(:conv_filters) >> comma >>
        str("kernel:") >> sp1 >> number.as(:conv_kernel)
    end
    rule(:m_maxpool) do
      str("layer") >> sp1 >> str("maxpool2d") >> sp1 >> str("size:") >> sp1 >> number.as(:pool_size)
    end
    rule(:m_batchnorm) { str("layer") >> sp1 >> str("batchnorm").as(:batchnorm) }
    rule(:m_flatten)   { str("layer") >> sp1 >> str("flatten").as(:flatten) }
    rule(:m_dense) do
      str("layer") >> sp1 >> str("dense") >> sp1 >> str("units:") >> sp1 >> number.as(:dense_units) >>
        (comma >> str("activation:") >> sp1 >> symbol.as(:dense_activation)).maybe
    end
    rule(:m_dropout) do
      str("layer") >> sp1 >> str("dropout") >> sp1 >> str("rate:") >> sp1 >> number.as(:dropout_rate)
    end
    rule(:m_output) do
      str("output") >> sp1 >> str("units:") >> sp1 >> number.as(:out_units) >>
        comma >> str("activation:") >> sp1 >> symbol.as(:out_activation)
    end
    rule(:m_greeting) do
      str("output") >> sp1 >> str("greeting") >> sp1 >> string.as(:greeting)
    end
    rule(:m_save) do
      str("save") >> sp1 >> str("weights") >> sp1 >> str("to") >> sp1 >> string.as(:save_path)
    end
    rule(:m_load) do
      str("load") >> sp1 >> str("weights") >> sp1 >> str("from") >> sp1 >> string.as(:load_path)
    end
    rule(:m_freeze) do
      str("freeze") >> sp1 >> str("until") >> sp1 >> symbol.as(:freeze_until)
    end
    rule(:m_unfreeze) { str("unfreeze") >> sp1 >> str("all").as(:unfreeze_all) }

    # ---- train ---------------------------------------------------------------
    rule(:train_stmt) do
      str("train") >> sp1 >> identifier.as(:tr_model) >> sp1 >> str("on") >> sp1 >>
        string.as(:tr_dataset) >> sp1 >> block_body(train_option, :tr_body) >> eol
    end
    rule(:train_option) do
      sp >> (
        (str("epochs") >> sp1 >> number.as(:epochs)) |
        (str("batch_size") >> sp1 >> number.as(:batch_size)) |
        (str("optimizer") >> sp1 >> symbol.as(:optimizer) >>
          (comma >> str("learning_rate:") >> sp1 >> number.as(:lr)).maybe) |
        (str("scheduler") >> sp1 >> symbol.as(:scheduler)) |
        (str("loss") >> sp1 >> symbol.as(:loss)) |
        (str("metrics") >> sp1 >> symbol.as(:metrics))
      ) >> eol
    end

    # ---- evaluate ------------------------------------------------------------
    rule(:evaluate_stmt) do
      str("evaluate") >> sp1 >> identifier.as(:ev_model) >> sp1 >> str("on") >> sp1 >>
        string.as(:ev_dataset) >> eol
    end

    # ---- route ---------------------------------------------------------------
    rule(:route_stmt) do
      str("route") >> sp1 >> string.as(:rt_path) >> sp1 >> identifier.as(:rt_method) >> sp1 >>
        block_body(route_line, :rt_body) >> eol
    end
    rule(:route_line) do
      sp >> (route_output | route_auth) >> eol
    end
    rule(:route_output) do
      str("output prediction from") >> sp1 >> identifier.as(:route_model) >>
        str(".predict(") >> identifier.as(:route_input) >> str(")") >>
        (sp1 >> str("format") >> sp1 >> symbol.as(:route_format)).maybe
    end
    rule(:route_auth) do
      str("authenticate with") >> sp1 >> symbol.as(:auth)
    end

    # ---- run -----------------------------------------------------------------
    rule(:run_stmt) { str("run web on port:") >> sp1 >> number.as(:port) >> eol }
  end
end
