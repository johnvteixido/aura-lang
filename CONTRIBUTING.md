# Contributing to Aura Framework

Welcome! We are excited that you want to contribute to Aura, the declarative AI Web Framework. This document provides guidelines for contributing to the project.

## 🏛️ Project Architecture
The compiler is a small pipeline of focused modules under `lib/aura/` (loaded by `lib/aura.rb`):
1.  **Parser (`lib/aura/parser.rb`)**: a `parslet` PEG grammar for the declarative syntax.
2.  **Transformer (`lib/aura/transformer.rb`)**: rewrites the raw parse tree into a flat list of semantic node hashes (helpers in `Aura::Nodes`).
3.  **Analyzer (`lib/aura/analyzer.rb`)**: semantic checks, e.g. references to undefined models.
4.  **Code generator (`lib/aura/codegen.rb` + `emitter.rb`)**: emits `Torch::NN::Module` subclasses, training loops, and classic-Sinatra handlers.
5.  **Diagnostics (`lib/aura/diagnostics.rb`)**: turns parse failures into `Aura::ParseError` with line/column.
6.  **CLI (`bin/aura`)**: project scaffolding, `run`/`check`/`build`/`deploy`.

## 🛠️ Development Setup
1.  **Clone**: `git clone https://github.com/johnvteixido/aura-lang`
2.  **Install Dependencies**: `bundle install`
    - *`torch-rb` is optional (it binds to LibTorch). The grammar, transpiler, and full test suite run without it. To run generated models locally, enable the ML group: `bundle config set --local with ml && bundle install`.*
3.  **Run Tests**: `bundle exec rake test`

## 🚀 Contribution Workflow
1.  **Fork and Branch**: Create a feature branch from `main`.
2.  **Grammar Changes**: If adding a new keyword, update `Aura::Parser` and ensure it doesn't break existing grammar rules.
3.  **Transformation & Codegen**: Add the corresponding rule in `Aura::Transformer` (and `Aura::Nodes` helper if needed), then implement the emission in `Aura::CodeGen`.
4.  **Tests**: Every new feature MUST include a test case under `tests/` (we use `Minitest`). New `.aura` syntax should also transpile to compilable Ruby — see `tests/test_examples.rb`.
5.  **Audit**: Run `bin/aura check` on your new features to verify the generated Ruby code.

## ⚖️ Standards
- **Declarative First**: Features should aim to simplify complex ML tasks into simple, readable keywords.
- **Production Grade**: Generated code should be class-based and follow Ruby best practices (e.g., using subclassing instead of dynamic evaluation where possible).
- **No Toys**: The framework's runtime relies on real `torch-rb` and `sinatra` primitives — core functionality is never mocked. (The test suite may stub LibTorch so the grammar/transpiler/route tests can run without a native build or GPU.)

## 📬 Submitting Changes
- Open a Pull Request with a clear description of the feature or bug fix.
- Ensure the CI (GitHub Actions) passes.
- Update the `README.md` or `examples/` if your change introduces new syntax.

Thank you for helping us build the future of AI web development! 🌟
