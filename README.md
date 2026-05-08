# 🌟 Aura: The Advanced AI Web Framework (v1.2.0)

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

## 🏗️ Commands
- `aura init <name>`: Scaffold a new production project.
- `aura run <file>`: Start your application.
- `aura build <file>`: Export to standalone Ruby.
- `aura deploy <file>`: Generate a production `Dockerfile`.
- `aura console`: Interactive debugging with app context.

## 📈 Roadmap
- [x] CNN & Convolutional Layers
- [x] Model Persistence (v1.1)
- [x] Transfer Learning & Schedulers (v1.2)
- [ ] Distributed Training (v1.3)
- [ ] Native RAG (Retrieval Augmented Generation) Primitives (v1.4)

## ☕ Support Aura Development
Aura is an open-source project by RootSpace.app. If you find the framework useful, please consider supporting its development.

**[Support Aura on Stripe (Choose what you pay)](https://donate.stripe.com/aura_framework)**  
*All donations go directly towards maintaining the infrastructure and developing new features like v1.3 Distributed Training.*

## 📜 License
MIT
