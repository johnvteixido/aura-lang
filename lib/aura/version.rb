# frozen_string_literal: true

module Aura
  # Single source of truth for the framework version. Referenced by the
  # gemspec, the CLI banner, and the generated-code header so they can never
  # drift apart again.
  VERSION = "1.2.2"
end
