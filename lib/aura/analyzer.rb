# frozen_string_literal: true

module Aura
  # Lightweight semantic pass over the node list. Catches the class of errors a
  # context-free grammar can't: referencing a model in `train`/`evaluate`/`route`
  # that was never defined. Stays silent for valid programs (only raises),
  # which keeps `Aura.transpile` free of side-effects.
  class Analyzer
    def self.analyze(nodes)
      new(nodes).analyze
    end

    def initialize(nodes)
      @nodes = nodes
    end

    def analyze
      defined_models = @nodes.select { |n| n[:type] == :model }.map { |n| n[:name] }

      @nodes.each do |node|
        case node[:type]
        when :train    then require_model!(defined_models, node[:model], "train")
        when :evaluate then require_model!(defined_models, node[:model], "evaluate")
        when :route    then require_model!(defined_models, node[:model], "route #{node[:path]}") if node[:model]
        end
      end

      @nodes
    end

    private

    def require_model!(defined_models, name, context)
      return if name.nil? || defined_models.include?(name)

      known = defined_models.empty? ? "(none)" : defined_models.join(", ")
      raise SemanticError, "Undefined model '#{name}' referenced in #{context}. Defined models: #{known}"
    end
  end
end
