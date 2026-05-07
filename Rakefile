# frozen_string_literal: true

require "rake/testtask"

Rake::TestTask.new(:test) do |t|
  t.libs    << "lib"
  t.pattern = "tests/test_*.rb"
  t.verbose = true
end

task default: :test
