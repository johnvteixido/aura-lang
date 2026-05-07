# 🌟 Aura: The Declarative AI Web Framework

[![Ruby Version](https://img.shields.io/badge/ruby-3.3%2B-brightgreen.svg)](https://ruby-lang.org)
[![Gem Version](https://img.shields.io/gem/v/aura-lang?color=blue)](https://rubygems.org/gems/aura-lang)

Aura is a **professional-grade AI Web Framework** that allows you to build, train, and deploy AI-powered web applications in a single declarative file. Built on top of **Torch-rb** and **Sinatra**, Aura combines the power of deep learning with the simplicity of modern web development.

## 🚀 Why Aura?
- **Single-File AI Apps**: Define your environment, neural network, training pipeline, and web routes in one cohesive `.aura` file.
- **Production Ready**: Transpiles to high-performance Ruby classes, using subclassing for models and Puma for serving.
- **Advanced ML Support**: Native support for CNNs (`Conv2D`, `MaxPool2d`), `BatchNorm`, `Dropout`, and `Dense` layers.
- **Seamless Deployment**: Use `aura build` to export your project into a standalone Sinatra application ready for any Ruby cloud provider.

## 🛠️ Quick Start
1. **Install**: `gem install aura-lang`
2. **Init**: `aura init my_app`
3. **Run**: `aura run my_app/app.aura`

## 🧠 Example: CNN Classifier
```aura
model vision neural_network do
  input shape(28, 28, 1) flatten
  layer conv2d filters: 32, kernel: 3
  layer maxpool2d size: 2
  layer batchnorm
  layer dense units: 128, activation: :relu
  output units: 10, activation: :softmax
end

route "/api/classify" post do
  output prediction from vision.predict(image) format :json
end

run web on port: 8080
```

## 🏗️ Commands
- `aura init <name>`: Scaffold a new project structure.
- `aura run <file>`: Start your application.
- `aura build <file>`: Export to standalone Ruby.
- `aura console`: Interactive debugging with app context.

## 📜 License
MIT
