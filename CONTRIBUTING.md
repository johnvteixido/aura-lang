# Contributing to Aura

Thank you for your interest in contributing to Aura! We're excited to build a forgiving, human-friendly declarative language for AI/ML and web apps together. Whether you're fixing bugs, adding features, improving documentation, or suggesting ideas, your help is welcome. This guide outlines how to contribute effectively.

Aura is an open-source project under the MIT License, inspired by Ruby's elegance and focused on developer happiness. We aim for a collaborative, inclusive community—let's keep it joyful and respectful.

## Code of Conduct
We adopt the [Contributor Covenant Code of Conduct](https://www.contributor-covenant.org/version/2/1/code_of_conduct.html). By participating, you agree to uphold this code. Please report unacceptable behavior to the project maintainers at LinkedIn, johnvteixido (update with actual maintainer email).

In short: Be kind, inclusive, and constructive. No harassment, discrimination, or toxicity.

## How Can I Contribute?
### Reporting Bugs
- Check if the issue exists in [GitHub Issues](https://github.com/johnvteixido/aura-lang/issues).
- If not, open a new issue with:
  - A clear title and description.
  - Steps to reproduce.
  - Expected vs. actual behavior.
  - Screenshots or code snippets.
  - Environment details (Ruby version, OS).
- Label it as "bug".

### Suggesting Features or Enhancements
- Open an issue with label "enhancement" or "feature".
- Describe the problem it solves.
- Propose a solution or API sketch.
- Discuss before implementing— we value community input!

### Documentation Improvements
- Fix typos, clarify examples, or add tutorials.
- Edit files in `/docs` (if exists) or README.md directly.
- PRs welcome—no issue needed for small fixes.

### Code Contributions
We love PRs! Focus areas:
- Parser improvements (Parslet grammar).
- Transpiler enhancements (e.g., more ML layers, real Hugging Face integration).
- Forgiveness features (e.g., better error suggestions).
- Web extensions (e.g., more route types, authentication).
- Tests (Minitest in `/tests`).
- Performance tweaks (e.g., optimize Torch-rb usage).

#### Setup for Development
1. Fork the repo: Click "Fork" on GitHub.
2. Clone your fork:
   ```
   git clone https://github.com/yourusername/aura-lang.git
   cd aura-lang
   ```
3. Install dependencies:
   ```
   gem install bundler
   bundle install
   ```
4. Run tests:
   ```
   bundle exec minitest tests/test_aura.rb
   ```
5. Make changes in a new branch:
   ```
   git checkout -b feature/your-feature
   ```
6. Test locally: `bin/aura run examples/your-test.aura`
7. Commit with clear messages (e.g., "feat: add conv2d layer support").
8. Push: `git push origin feature/your-feature`
9. Open a PR against the main branch.

#### PR Guidelines
- Keep PRs small and focused—one feature/fix per PR.
- Follow Ruby style (use RuboCop if we add it).
- Add tests for new features.
- Update docs/examples if relevant.
- Reference issues (e.g., "Fixes #123").
- Be patient—maintainers will review ASAP.
- We'll merge if it aligns with the roadmap and passes CI (add GitHub Actions if not set up).

### First-Time Contributors
New to open-source? Start with issues labeled "good first issue" or "help wanted". Ask questions in issues—we're here to help!

### Recognition
All contributors are credited in AUTHORS.md (create if needed) or README. Major contributors may be invited as maintainers.

## Questions?
- Open an issue for discussions.
- Reach out on LinkedIn @johnvteixido.

Thanks for contributing to Aura—let's make AI and web dev more joyful! 🌟
