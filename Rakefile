# frozen_string_literal: true

begin
  require "bundler/gem_tasks" # build / install / release from the gemspec
rescue LoadError
  # Bundler not available; build/release tasks are skipped but `rake test` works.
end

require "rake/testtask"

Rake::TestTask.new(:test) do |t|
  t.libs    << "lib"
  t.pattern = "tests/test_*.rb"
  t.verbose = true
end

task default: :test

# --- Release helpers ---------------------------------------------------------
# One-command version bumps. `rake bump:patch` rewrites lib/aura/version.rb and
# stamps a fresh CHANGELOG heading. Then commit, tag vX.Y.Z, and push the tag --
# the GitHub Action (.github/workflows/ruby-gem-push.yml) publishes the gem.
VERSION_FILE   = File.expand_path("lib/aura/version.rb", __dir__)
CHANGELOG_FILE = File.expand_path("CHANGELOG.md", __dir__)

def aura_bump(part)
  current = File.read(VERSION_FILE)[/VERSION\s*=\s*"([^"]+)"/, 1]
  major, minor, patch = current.split(".").map(&:to_i)
  case part
  when :major then major, minor, patch = major + 1, 0, 0
  when :minor then minor, patch = minor + 1, 0
  when :patch then patch += 1
  end
  nextv = "#{major}.#{minor}.#{patch}"
  File.write(VERSION_FILE, File.read(VERSION_FILE).sub(/VERSION\s*=\s*"[^"]+"/, %(VERSION = "#{nextv}")))
  aura_stamp_changelog(nextv)
  puts "Bumped #{current} -> #{nextv}"
  puts %(Next: git commit -am "Release v#{nextv}" && git tag v#{nextv} && git push origin HEAD --tags)
end

def aura_stamp_changelog(version)
  return unless File.exist?(CHANGELOG_FILE)

  body = File.read(CHANGELOG_FILE)
  return if body.include?("## [#{version}]")

  entry = "## [#{version}] - #{Time.now.strftime('%Y-%m-%d')}\n\n- _Describe changes here._\n\n"
  updated = body =~ /^## \[/ ? body.sub(/^## \[/, entry + "## [") : "#{body}\n#{entry}"
  File.write(CHANGELOG_FILE, updated)
end

namespace :bump do
  desc "Bump patch version (x.y.Z)"
  task(:patch) { aura_bump(:patch) }
  desc "Bump minor version (x.Y.0)"
  task(:minor) { aura_bump(:minor) }
  desc "Bump major version (X.0.0)"
  task(:major) { aura_bump(:major) }
end
