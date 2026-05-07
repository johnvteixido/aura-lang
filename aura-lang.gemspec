Gem::Specification.new do |s|
  s.name        = "aura-lang"
  s.version     = "1.0.0"
  s.summary     = "Aura: The Declarative AI Web Framework"
  s.description = "A professional-grade framework for building AI pipelines and AI-integrated web apps with Ruby and Torch."
  s.authors     = ["John V Teixido"]
  s.email       = "johnvteixido@github.com"
  s.files       = Dir["{bin,lib,examples}/**/*", "README.md", "LICENSE", "Rakefile", "aura-lang.gemspec"]
  s.homepage    = "https://github.com/johnvteixido/aura-lang"
  s.license     = "MIT"
  s.executables << "aura"
  s.add_dependency "parslet", "~> 2.0"
  s.add_dependency "torch-rb", "~> 0.10"
  s.add_dependency "sinatra", "~> 4.2"
  s.add_dependency "puma", "~> 7.2"
  s.add_dependency "json", "~> 2.7"
  s.add_dependency "datasets", "~> 0.1"
  s.add_dependency "dotenv", "~> 3.1"
end
