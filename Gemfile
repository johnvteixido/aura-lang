source "https://rubygems.org"

gemspec

# Torch is only needed to train/run generated models, and it binds to LibTorch
# on the host. It lives in an optional group so `bundle install` (and CI) works
# without LibTorch present. Enable it when you want to run models:
#   bundle config set --local with ml && bundle install
group :ml, optional: true do
  gem "torch-rb", "~> 0.10"
end

group :development, :test do
  gem "pry",      "~> 0.14"
  gem "rerun",    "~> 0.14"
  gem "minitest", "~> 6.0"
  gem "rake",     "~> 13.0"
end
