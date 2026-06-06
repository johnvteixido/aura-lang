# Releasing Aura

Aura publishes to [RubyGems](https://rubygems.org/gems/aura-lang) automatically
from CI. The version is single-sourced in `lib/aura/version.rb` (the gemspec and
the CLI/codegen banners all read `Aura::VERSION`), so a release is a one-line
bump plus a tag.

## One-time setup (gem owner only)

The publish workflow uses **RubyGems Trusted Publishing** (OIDC) — there is no
long-lived API key to store or rotate. Configure it once:

1. Sign in to <https://rubygems.org> as the `aura-lang` owner.
2. Go to the gem's **Settings → Trusted Publishers → Add a new publisher**
   (for a brand-new gem, use **Create a pending trusted publisher** so the first
   release can publish before the gem exists).
3. Choose **GitHub Actions** and enter:
   - Repository: `johnvteixido/aura-lang`
   - Workflow filename: `ruby-gem-push.yml`
   - (Environment: leave blank.)

That's it — the `id-token: write` permission in the workflow lets CI mint a
short-lived RubyGems credential at publish time.

> Prefer an API key instead? Set a `RUBYGEMS_API_KEY` repository secret and
> replace the *Configure RubyGems credentials* + *Publish to RubyGems* steps in
> `.github/workflows/ruby-gem-push.yml` with a single
> `run: gem push *.gem` step using `env: { GEM_HOST_API_KEY: ${{ secrets.RUBYGEMS_API_KEY }} }`.

## Cutting a release

```bash
# 1. Bump the version (rewrites lib/aura/version.rb + stamps CHANGELOG.md).
rake bump:patch      # or bump:minor / bump:major

# 2. Edit the new CHANGELOG.md section, then commit.
git commit -am "Release v$(ruby -Ilib -raura -e 'print Aura::VERSION')"

# 3. Tag and push -- this triggers the publish workflow.
git tag "v$(ruby -Ilib -raura -e 'print Aura::VERSION')"
git push origin HEAD --tags
```

Pushing the `vX.Y.Z` tag (or publishing a GitHub Release) runs
`.github/workflows/ruby-gem-push.yml`, which tests, builds the gem, and pushes
it to both RubyGems and GitHub Packages.

## Build / verify locally

```bash
rake build                       # builds pkg/aura-lang-X.Y.Z.gem
gem spec pkg/aura-lang-*.gem version   # confirm the version
```
