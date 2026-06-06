# Changelog

All notable changes to Aura are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/), and the project aims to follow
[Semantic Versioning](https://semver.org/).

## [1.2.1]

### Fixed
- Inline and trailing `# ...` comments are stripped before parsing (previously
  only full-line comments were). `#` inside string literals is preserved.
- Numeric literals support scientific notation (`1e-4`) and negative values;
  string literals support escaped quotes (`\"`).
- Generated apps start the web server under `aura run` (emit `set :run, true`).
- Use the correct Torch CUDA API (`Torch::CUDA.available?`).
- Route handlers read the request payload using the key named in
  `model.predict(<key>)` rather than a fixed key.

### Added
- Complete training and evaluation loops: forward/backward/optimizer step,
  optional accuracy metric, learning-rate scheduler stepping, and an automatic
  `save weights` call after training.
- Dataset loading for the bundled red-datasets sets (MNIST, Fashion-MNIST,
  CIFAR), with a clear error and extension point for other sources.
  Environment variables are loaded from `.env` via dotenv.
- Transfer-learning models apply `freeze` / `unfreeze all` to the pretrained
  backbone and build a classification head from `output units:`.
- Bearer-token authentication for `authenticate with`
  (`Authorization: Bearer <token>`).
- Semantic validation for duplicate model names and duplicate routes.
- Vercel deployment for LLM-only apps via `aura deploy <file> --target vercel`
  (generates `vercel.json` and a Rack entrypoint); Torch apps are directed to
  the container/`Dockerfile` path.
- Runtime test suite that boots generated apps and exercises their routes.

### Changed
- The gem version is sourced from `Aura::VERSION` (single source of truth).
- Added `rake build` / `rake release` and `rake bump:patch|minor|major`.
- The release workflow runs the full test suite, triggers on version tags, and
  publishes to RubyGems via Trusted Publishing (OIDC).

## [1.2.0]

This release makes the framework actually implement what it has long advertised.
Previously the transpiler parsed the DSL but emitted little real code (models
compiled to an identity `forward`, training/routes/datasets produced nothing,
and `aura deploy` referenced a method that did not exist). The compiler has been
rebuilt into a real, modular pipeline.

### Added
- **Real neural-network code generation.** `neural_network` models now compile
  to `Torch::NN::Module` subclasses with a genuine `forward` pass. Supported
  layers: `input shape(...)` (with optional `do ... end` preprocessing block),
  `input text`, `conv2d`, `maxpool2d`, `batchnorm`, `flatten`, `dense`,
  `dropout`, and `output`. Tensor shapes are tracked so `Conv2d` in-channels and
  `Linear` in-features are computed automatically.
- **Real training loops.** `train` emits optimizer, loss criterion, optional LR
  scheduler, and an epoch loop. New options: `batch_size`, `metrics`.
- **Web serving.** `route` blocks compile to classic-Sinatra handlers (with
  `format :json`, `authenticate with`), and `run web on port:` boots the server.
- **LLM models.** `model <name> from openai "..."` / `from ollama "..."` compile
  to HTTP client methods (no training loop emitted for LLM models).
- **`evaluate <model> on "..."`**, **environment config** (`class AuraConfig`),
  **dataset** declarations, and model persistence (`save weights to` /
  `load weights from`).
- **`Aura.parse`** public entry point and **`Aura.build_docker`** (backs
  `aura deploy`, generating a `Dockerfile` + `.dockerignore`).
- **Diagnostics.** Parse failures become `Aura::ParseError` with line/column and
  a source snippet; a semantic pass raises `Aura::SemanticError` for references
  to undefined models in `train`/`route`/`evaluate`.
- **Comment support** (`# ...`) in `.aura` files, plus tolerance for blank lines.
- New tests: `test_examples.rb` (every example/scaffold transpiles to compilable
  Ruby) and `test_diagnostics.rb`.

### Changed
- The compiler was split from a single `lib/aura.rb` into focused modules under
  `lib/aura/` (`parser`, `transformer`, `analyzer`, `codegen`, `emitter`,
  `diagnostics`, `docker`, `version`).
- Code generation uses an indentation-aware emitter instead of string
  concatenation, and classic Sinatra (`require "sinatra"`).
- `aura init` now scaffolds a parseable app and reports `Created Aura project`;
  `aura run <missing>` writes a starter template; CLI output is ASCII-only.
- `torch-rb` is now an **optional** dependency (required only to run models), so
  the gem installs and CI passes without LibTorch present.
- Version is sourced from a single `Aura::VERSION` constant (the CLI banner no
  longer drifts from the gem version).

### Removed
- Stray scratch files committed at the repo root and a checked-in `*.gem` build
  artifact.
