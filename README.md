# 🌟 Aura

[![Ruby Version](https://img.shields.io/badge/ruby-3.3%2B-brightgreen.svg)](https://ruby-lang.org)
[![Gem Version](https://img.shields.io/gem/v/aura-lang?color=blue)](https://rubygems.org/gems/aura-lang)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![GitHub Stars](https://img.shields.io/github/stars/johnvteixido/aura-lang?style=social)](https://github.com/johnvteixido/aura-lang)

Aura is a **forgiving, human-friendly declarative language** designed specifically for building AI/ML pipelines and fast, AI-integrated web applications. Drawing inspiration from the elegance and developer happiness of Ruby (think Rails' magic but for AI and web), Aura aims to reduce boilerplate, eliminate common errors, and make prototyping joyful. 

Whether you're a data scientist iterating on neural networks, a web developer embedding AI features, or a hobbyist exploring ML, Aura provides a natural, expressive syntax that feels like writing pseudocode—while transpiling to efficient Ruby code powered by Torch-rb and Sinatra for speed and scalability.

Launched in late 2025, Aura is in its early stages (v0.1) but already supports basic ML workflows and web serving. Join us in shaping a language that prioritizes **programmer happiness** over strictness.

## Why Aura?
In a world dominated by verbose Python scripts for ML (PyTorch/TensorFlow) and fragmented web stacks (Next.js + APIs), Aura bridges the gap:
- **Human-Readable Syntax**: Ruby-like blocks and natural keywords make code read like English.
- **Forgiving by Design**: Smart defaults, auto-inference (e.g., tensor shapes, devices), and friendly error suggestions (e.g., "OOM? Halving batch size for you! 😊").
- **AI/Web Integration**: Seamless from data loading to model training to deploying AI endpoints— all in one file.
- **Fast Performance**: Transpiles to Ruby with Torch-rb for ML and Puma/Sinatra for concurrent web serving. No slow interpreters.
- **Zero Boilerplate**: No `__init__.py`, no manual imports— just declare and run.
- **Interoperable**: Outputs standard Ruby code; easy to extend or integrate with existing ecosystems.

Aura fills the niche for "conversational coding" in AI, where iteration speed and error resilience matter most. If you've ever debugged shape mismatches in PyTorch or wrestled with web deployment, Aura is for you.

## Features
- **Declarative ML Pipelines**: Define datasets, models, training, and evaluation in concise blocks.
- **Built-in Forgiveness**:
  - Auto-device selection (GPU if available).
  - Runtime recovery (e.g., reduce batch size on memory errors).
  - Plain-English errors with fix suggestions.
- **Web Primitives**: Routes with AI hooks (e.g., predict on user input) transpiled to fast Sinatra apps.
- **Extensible**: Add custom layers or integrations via Ruby extensions.
- **MVP Scope**: Supports simple neural nets (dense, dropout), mock/Hugging Face data, JSON/HTML responses.
- **Future-Proof**: Roadmap includes real LLM integration, full Hugging Face support, and one-click deploys.

## Installation
Aura is distributed as a Ruby gem. Requires Ruby 3.3+.

1. Install Ruby (if not already): [ruby-lang.org](https://www.ruby-lang.org/en/downloads/).
2. Clone the repo:
   ```
   git clone https://github.com/johnvteixido/aura-lang.git
   cd aura-lang
   ```
3. Install dependencies:
   ```
   gem install bundler
   bundle install
   ```
   This pulls in Parslet (for parsing), Torch-rb (for ML), Sinatra/Puma (for web), and dev tools like Pry.

For global CLI access:
```
gem install aura-lang
```

## Quick Start
1. Create a `.aura` file (e.g., `hello.aura`):
   ```aura
   model greeter neural_network do
     input text
     output greeting "Hello from Aura! 🌟"
   end

   route "/hello" get do
     output prediction from greeter.predict(input) format :json
   end

   run web on port: 3000
   ```
2. Run it:
   ```
   bin/aura run hello.aura
   ```
   This transpiles to Ruby, "trains" (mock), and starts a server.
3. Test: `curl http://localhost:3000/hello` → `{"prediction": "Hello from Aura! 🌟"}`

For errors, Aura suggests fixes automatically—e.g., "Missing 'end'? Added it for you! 😊"

## Usage
Aura files (`.aura`) are declarative scripts. The CLI transpiles and executes them:
- `aura run <file.aura>`: Parse, transpile, run (trains models, starts web server).
- Future: `aura deploy <file.aura>` for cloud (Vercel/Fly.io).

Key Commands:
- `aura --help`: Usage info.
- `aura repl`: Interactive mode (roadmap).

## Examples
### Basic ML Pipeline (mnist_classifier.aura)
Train a simple classifier and serve predictions:
```aura
dataset "mnist" from huggingface "mnist"

model classifier neural_network do
  input shape(28, 28, 1) flatten
  layer dense units: 128, activation: :relu
  layer dropout rate: 0.2
  output units: 10, activation: :softmax
end

train classifier on "mnist" do
  epochs 5
  batch_size 32
  optimizer :adam, learning_rate: 0.001
  loss :cross_entropy
  metrics :accuracy
end

evaluate classifier on "mnist/test"

route "/predict" post do
  output prediction from classifier.predict(image) format :json
end

run web on port: 3000
```
Run: `bin/aura run mnist_classifier.aura`
- Trains on mock data (real HF coming soon).
- POST to /predict: `curl -X POST http://localhost:3000/predict -d '{"image": [[...28x28 array...]]}'`

### Simple Web App with AI
```aura
route "/recommend" get do
  output prediction from recommender.predict(user_id) format :html
end

run web on port: 8080
```
Outputs dynamic HTML with AI-driven content.

## Syntax Overview
- **Blocks**: Use `do ... end` for models, trains, routes.
- **Keywords**: Natural like `layer dense units: 128`.
- **Defaults**: Many inferred (e.g., activation: :relu).
- **Formats**: JSON/HTML for outputs.
Full grammar in `lib/aura.rb` (Parslet-based).

## Philosophy
Inspired by David Heinemeier Hansson (DHH) and Ruby on Rails:
- **Beautiful over Clever**: Code should read like a story.
- **Forgiving over Strict**: Help users recover from mistakes.
- **Human Happiness First**: Optimize for joy, not performance alone.
- **Zero Boilerplate**: No ceremony—just create.
We believe languages should empower, not frustrate. Aura is our attempt at "Ruby for AI in 2025."

## Roadmap
- v0.2: Real Hugging Face dataset loading, more layers (conv2d, LSTM).
- v0.3: LLM integration (e.g., Ollama hooks), REPL mode.
- v1.0: Native compilation (via MRuby?), full web frameworks (Hanami/Rails interop), community extensions.
- Long-term: Visual editor, enterprise features (federated learning).

Track issues/PRs on GitHub.

## Contributing
We ❤️ contributions! 
1. Fork the repo.
2. Create a branch: `git checkout -b feature/awesome-thing`.
3. Commit changes: `git commit -m "Add awesome thing"`.
4. Push: `git push origin feature/awesome-thing`.
5. Open a PR.

See CONTRIBUTING.md (coming soon) for guidelines. Focus on parser/transpiler extensions or examples.

## License
MIT License. See [LICENSE](LICENSE) for details.

## Acknowledgments
- Ruby community for endless inspiration.
- Torch-rb for ML power.
- You, for checking out Aura! 🌟

Questions? Open an issue or tweet @johnvteixido (assuming your handle). Let's build the future of AI coding together!
