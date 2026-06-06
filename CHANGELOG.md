# Changelog

All notable changes to Aura are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/), and the project aims to follow
[Semantic Versioning](https://semver.org/).

## [1.2.1]

A correctness and feature-completion pass. The v1.2.0 test suite only ever
*compiled* generated Ruby; this release adds tests that actually **run** it,
fixes the real bugs that surfaced, and turns several parsed-but-stubbed features
into working code.

### Fixed
- **Inline/trailing comments** (`scheduler :step_lr # note`) now parse. Only
  full-line comments worked before -- which meant the README's own headline
  example did not parse. `#` inside string literals is preserved.
- **Numbers**: scientific notation (`1e-4`) and negative values (`-1`, `-0.001`)
  now parse; escaped quotes (`\"`) are allowed inside strings.
- **`aura run` now boots the server.** Generated apps emit `set :run, true`, so
  classic Sinatra starts even when the app is loaded via `eval`/`require`.
- **Correct Torch CUDA API** (`Torch::CUDA.available?` instead of the
  non-existent `Torch.cuda_available?`).
- **Routes read the right payload key** -- the variable named in
  `model.predict(<var>)` is used as the JSON key (e.g. `payload["image"]`),
  instead of a hard-coded `"input"`/`"message"`.

### Added / completed
- **Real training & evaluation loops.** `train` streams batches and runs
  zero-grad → forward → loss → backward → step, reports per-epoch loss/accuracy
  (when `metrics :accuracy`), steps the LR scheduler, and calls the model's
  `save weights` helper when declared. `evaluate` runs a no-grad accuracy pass.
- **Dataset loading.** A generated `aura_each_batch` helper wires up
  `red-datasets` for MNIST / Fashion-MNIST / CIFAR (and raises a clear,
  actionable error for unsupported sources). `dotenv` is loaded so API keys/
  tokens come from `.env`/the environment. (Both gems were dependencies that
  nothing used before.)
- **Transfer learning** now uses the model body: `freeze`/`unfreeze all` toggle
  the pretrained backbone's `requires_grad`, and `output units:` builds a real
  classification head with the chosen activation. (`torchvision` is required
  when a transfer model is present.)
- **Real bearer-token auth** for `authenticate with` (checks
  `Authorization: Bearer <AURA_API_TOKEN>`), replacing the presence-only check.
- **Validation**: duplicate model names and duplicate route `verb + path`
  combinations now raise `Aura::SemanticError`.
- **Vercel deployment** for LLM-only apps: `aura deploy <file> --target vercel`
  emits `vercel.json` + `api/index.rb`; it refuses Torch apps (which exceed
  serverless limits) and points to the container path. See `DEPLOY.md`.
- **Runtime tests** (`tests/test_runtime.rb`) that boot generated apps with a
  stubbed Torch and drive routes via `Rack::MockRequest`, plus parse/validation/
  transfer/feature coverage. Suite grew from 26 to 42 examples.

### Packaging
- The gemspec version is now sourced from `Aura::VERSION` (no more drift).
- `rake build` / `rake release` (via `bundler/gem_tasks`) and
  `rake bump:patch|minor|major` for one-command version bumps.
- The publish workflow's broken test step is fixed, it triggers on `vX.Y.Z`
  tags as well as releases, and it uses RubyGems **Trusted Publishing** (OIDC)
  instead of a stored API key. See `RELEASING.md`.

> Note: real Torch training/inference is compile-verified and follows the
> torch-rb API, but is not executed in CI (LibTorch isn't installed); the Vercel
> handler is asset-validated, not live-deployed.

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
