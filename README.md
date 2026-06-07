# 🌟 Aura: The Advanced AI Web Framework (v1.2.2)

**A [RootSpace.app](https://rootspace.app) Product**  
**Founded and Developed by [John V. Teixido](https://github.com/johnvteixido)**

[![Ruby Version](https://img.shields.io/badge/ruby-3.3%2B-brightgreen.svg)](https://ruby-lang.org)
[![Gem Version](https://img.shields.io/gem/v/aura-lang?color=blue)](https://rubygems.org/gems/aura-lang)

Aura is a **professional-grade AI Web Framework** that allows you to build, train, and deploy advanced AI models in a single declarative file. By combining **Torch-rb**, **Torchvision**, and **Sinatra**, Aura bridges the gap between deep learning research and production web services.

## 🚀 Key Features
- **Transfer Learning (New)**: Bootstrap your models with pre-trained architectures (ResNet, BERT, etc.) using `transfer from :model_name`.
- **Advanced Training**: Declarative Learning Rate Schedulers (`StepLR`, `ExponentialLR`) and Optimizer configurations.
- **Model Persistence**: Native `save` and `load` primitives for model weights.
- **Production Infrastructure**: Transpiles to class-based Ruby using `Torch::NN::Module` subclassing and Puma for high-performance serving.
- **Seamless Deployment**: Generate production-ready Dockerfiles with `aura deploy`.

## 🛠️ Installation
```bash
gem install aura-lang
```

> **Torch is optional.** Parsing, transpiling (`aura check`), and building
> (`aura build` / `aura deploy`) work out of the box. Training and running
> models additionally require [`torch-rb`](https://github.com/ankane/torch.rb)
> and LibTorch: `gem install torch-rb`.

### 🔨 Local Installation (From Source)
If you are developing Aura or want to use the latest unreleased version:
```bash
git clone https://github.com/johnvteixido/aura-lang
cd aura-lang
gem build aura-lang.gemspec
gem install ./aura-lang-1.2.2.gem
```

## 🧠 Example: Transfer Learning Image API
Build a professional Image Classifier in seconds:

```aura
# Scaffolding a production vision API
environment production do
  device :cuda
  log_level :info
end

model vision transfer from :resnet18 do
  # Fine-tune the head while keeping features frozen
  freeze until :layer_4
  output units: 10, activation: :softmax
end

train vision on "imagenet-subset" do
  epochs 20
  optimizer :adam, learning_rate: 0.0001
  scheduler :step_lr # Advanced LR scheduling
end

route "/v1/classify" post do
  authenticate with :token
  output prediction from vision.predict(image)
end

run web on port: 8080
```

> **What runs out of the box:** `aura check` / `build` / `deploy` transpile this
> to a standalone Sinatra app with no extra setup. **Training and serving** need
> [`torch-rb`](https://github.com/ankane/torch.rb) + LibTorch installed.
> Built-in dataset loading covers the [red-datasets](https://github.com/red-data-tools/red-datasets)
> sets (MNIST / Fashion-MNIST / CIFAR); for any other dataset, the generated
> loader raises with a clear hook so you can plug your own in.

## 🏗️ Commands
- `aura init <name>`: Scaffold a new production project.
- `aura train <file>`: Train the models, persist weights, then exit.
- `aura run <file>`: Serve the app (loads saved weights; does **not** retrain).
- `aura check <file>`: Transpile and preview the generated Ruby.
- `aura build <file>`: Export to standalone Ruby.
- `aura deploy <file>`: Generate a production `Dockerfile` (add `--target vercel` for LLM-only apps).
- `aura console`: Interactive debugging with app context.

> Training and serving are separate: `aura train` runs the `train`/`evaluate`
> blocks and saves weights; `aura run` loads those weights and serves, so the
> server never retrains on boot.

## 🚢 Deployment
- **Torch apps** (neural networks, transfer learning, training) run on a
  container host (Fly.io, Render, Cloud Run; GPU via Modal or Replicate).
  `aura deploy <file>` generates a production `Dockerfile`. Torch model servers
  need LibTorch and a long-lived process, so they are not suited to serverless
  platforms.
- **LLM-only / text apps** (`from openai` / `from ollama`) run on Vercel's Ruby
  runtime via `aura deploy <file> --target vercel`, or on any container host.

## 📈 Roadmap
- [x] CNN & Convolutional Layers
- [x] Model Persistence (v1.1)
- [x] Transfer Learning & Schedulers (v1.2)
- [ ] Distributed Training (v1.3)
- [ ] Native RAG (Retrieval Augmented Generation) Primitives (v1.4)

## ☕ Support Aura Development
Aura is an open-source project by RootSpace.app. If you find the framework useful, please consider supporting its development.

**[Support Aura on Stripe (Choose what you pay)](https://donate.stripe.com/9B66oH2hHbci9ZNd5jc7u00)**  
*All donations go directly towards maintaining the infrastructure and developing new features like v1.3 Distributed Training.*

## 📜 License
MIT
