# frozen_string_literal: true

module Aura
  # Lightweight semantic pass over the node list. Catches the class of errors a
  # context-free grammar can't: referencing a model in `train`/`evaluate`/`route`
  # that was never defined. Stays silent for valid programs (only raises),
  # which keeps `Aura.transpile` free of side-effects.
  class Analyzer
    KNOWN_PROVIDERS = %i[openai ollama].freeze
    HTTP_VERBS      = %w[get post put patch delete options head].freeze

    def self.analyze(nodes)
      new(nodes).analyze
    end

    def initialize(nodes)
      @nodes = nodes
    end

    def analyze
      defined_models = @nodes.select { |n| n[:type] == :model }.map { |n| n[:name] }
      check_unique_models!(defined_models)
      check_unique_routes!
      check_providers!
      check_http_verbs!

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

    # LLM models compile to a provider-specific HTTP client; an unknown provider
    # would otherwise be silently treated as OpenAI.
    def check_providers!
      @nodes.each do |node|
        next unless node[:type] == :model && node[:kind] == :llm
        next if KNOWN_PROVIDERS.include?(node[:provider])

        raise SemanticError,
              "Unknown LLM provider '#{node[:provider]}' for model '#{node[:name]}'. " \
              "Supported: #{KNOWN_PROVIDERS.join(', ')}."
      end
    end

    # A route's verb becomes a Sinatra DSL method; reject anything that isn't a
    # real HTTP verb so it fails at compile time, not at boot.
    def check_http_verbs!
      @nodes.each do |node|
        next unless node[:type] == :route
        next if HTTP_VERBS.include?(node[:method].to_s.downcase)

        raise SemanticError,
              "Unsupported HTTP method '#{node[:method]}' in route #{node[:path]}. " \
              "Supported: #{HTTP_VERBS.join(', ')}."
      end
    end

    # A model name must be unique: two definitions would both generate the same
    # class/accessor, silently shadowing one another.
    def check_unique_models!(names)
      dups = names.group_by(&:itself).select { |_, v| v.size > 1 }.keys
      return if dups.empty?

      raise SemanticError,
            "Duplicate model name#{'s' if dups.size > 1}: #{dups.join(', ')}. Each model must have a unique name."
    end

    # The same HTTP verb + path can't be routed twice -- the second handler
    # would be unreachable.
    def check_unique_routes!
      seen = {}
      @nodes.select { |n| n[:type] == :route }.each do |route|
        key = "#{route[:method].to_s.upcase} #{route[:path]}"
        raise SemanticError, "Duplicate route: #{key} is defined more than once." if seen[key]

        seen[key] = true
      end
    end

    def require_model!(defined_models, name, context)
      return if name.nil? || defined_models.include?(name)

      known = defined_models.empty? ? "(none)" : defined_models.join(", ")
      raise SemanticError, "Undefined model '#{name}' referenced in #{context}. Defined models: #{known}"
    end
  end
end
