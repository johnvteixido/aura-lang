require_relative "lib/aura/version"

Gem::Specification.new do |s|
  s.name        = "aura-lang"
  s.version     = Aura::VERSION
  s.summary     = "Aura: The Declarative AI Web Framework"
  s.description = "A professional-grade framework for building AI pipelines and AI-integrated web apps with Ruby and Torch."
  s.authors     = ["John V Teixido"]
  s.email       = "johnvteixido@users.noreply.github.com"
  s.files       = Dir["{bin,lib,examples}/**/*", "README.md", "CHANGELOG.md", "LICENSE", "Rakefile", "aura-lang.gemspec"]
  s.homepage    = "https://rootspace.app"
  s.license     = "MIT"
  s.required_ruby_version = ">= 3.2"
  s.executables << "aura"

  # Core dependencies needed to parse, transpile, and serve Aura apps.
  s.add_dependency "parslet", "~> 2.0"
  s.add_dependency "sinatra", "~> 4.2"
  s.add_dependency "puma", ">= 7.2", "< 9.0"
  s.add_dependency "json", "~> 2.7"
  s.add_dependency "red-datasets", "~> 0.1"
  s.add_dependency "dotenv", "~> 3.1"

  # NOTE: `torch-rb` (and the LibTorch native library it binds to) is required
  # only to *train and run* generated models, not to parse/transpile/build.
  # It is intentionally an optional runtime dependency so the gem installs in
  # environments without LibTorch. Install it explicitly to run models:
  #   gem install torch-rb
end
