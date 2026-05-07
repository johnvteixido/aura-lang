# Contributing to Aura Framework

Welcome! We are excited that you want to contribute to Aura, the declarative AI Web Framework. This document provides guidelines for contributing to the project.

## 🏛️ Project Architecture
Aura is divided into three main layers:
1.  **The Parser (`lib/aura.rb`)**: Uses the `parslet` gem to define the declarative grammar.
2.  **The Transformer/Transpiler (`lib/aura.rb`)**: Converts the AST into production-grade Ruby code using `Torch::NN::Module` and `Sinatra`.
3.  **The CLI (`bin/aura`)**: Handles project scaffolding, execution, and deployment.

## 🛠️ Development Setup
1.  **Clone**: `git clone https://github.com/johnvteixido/aura-lang`
2.  **Install Dependencies**: `bundle install`
    - *Note: Requires LibTorch to be installed on your system for `torch-rb`.*
3.  **Run Tests**: `bundle exec rake test`

## 🚀 Contribution Workflow
1.  **Fork and Branch**: Create a feature branch from `main`.
2.  **Grammar Changes**: If adding a new keyword, update the `Aura::Parser` and ensure it doesn't break existing grammar rules.
3.  **Transformation**: Add the corresponding rule in `Aura::Transformer` and implement the code generation logic in `Aura.transpile`.
4.  **Tests**: Every new feature MUST include a test case in `tests/test_aura.rb`. We use `Minitest`.
5.  **Audit**: Run `bin/aura check` on your new features to verify the generated Ruby code.

## ⚖️ Standards
- **Declarative First**: Features should aim to simplify complex ML tasks into simple, readable keywords.
- **Production Grade**: Generated code should be class-based and follow Ruby best practices (e.g., using subclassing instead of dynamic evaluation where possible).
- **No Toys**: We do not use mock libraries or stubs for core functionality. Contributions should rely on real `torch-rb` and `sinatra` primitives.

## 📬 Submitting Changes
- Open a Pull Request with a clear description of the feature or bug fix.
- Ensure the CI (GitHub Actions) passes.
- Update the `README.md` or `examples/` if your change introduces new syntax.

Thank you for helping us build the future of AI web development! 🌟
