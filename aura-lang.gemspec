Gem::Specification.new do |s|
  s.name        = "aura-lang"
  s.version     = "0.1.0"
  s.summary     = "Aura: A beautiful declarative language for AI and web"
  s.description = "Forgiving, Ruby-inspired DSL for ML pipelines and fast AI-powered web apps"
  s.authors     = ["John V Teixido"]
  s.email       = "johnvteixido@github.com"
  s.files       = Dir["{bin,lib,examples}/**/*", "README.md", "LICENSE", ".gitignore", "aura-lang.gemspec"]
  s.homepage    = "https://github.com/johnvteixido/aura-lang"
  s.license     = "MIT"
  s.executables << "aura"
  s.add_dependency "parslet", "~> 2.0"
  s.add_dependency "torch-rb", "~> 0.10"
  s.add_dependency "sinatra", "~> 4.2"
  s.add_dependency "puma", "~> 7.2"
  s.add_dependency "json", "~> 2.7"
end
