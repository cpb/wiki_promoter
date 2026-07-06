# RubyGems Release Setup

`.github/workflows/release.yml` publishes `wiki_promoter` to
[rubygems.org](https://rubygems.org) whenever a `v*` tag is pushed. It builds
the gem with `rake build` and runs `gem push` using a `RUBYGEMS_API_KEY`
secret written to `~/.gem/credentials`.

## One-time setup

1. Create (or use an existing) rubygems.org account.
2. Under **Profile → API Keys**, create a key scoped to "Push rubygem"
   (optionally restricted to the `wiki_promoter` gem so a leaked key can't
   push other gems).
3. Add it as a GitHub Actions repo secret:
   `gh secret set RUBYGEMS_API_KEY --repo cpb/wiki_promoter`, or via
   **Settings → Secrets and variables → Actions** in the GitHub UI.

## Cutting a release

1. Bump the version in `lib/wiki_promoter/version.rb`.
2. Update `CHANGELOG.md`.
3. Commit the bump, then tag and push:
   ```bash
   git tag v0.2.0
   git push origin v0.2.0
   ```
4. The `release` workflow builds and pushes the gem — no manual `gem push`.

## Local secrets

`RUBYGEMS_API_KEY` is only consumed by the GitHub Actions workflow; nothing
in this repo reads it locally. `WIKI_DEPLOY_TOKEN`, by contrast, **is** needed
locally to dogfood wiki promotion (see
[`.env.sample`](https://github.com/cpb/wiki_promoter/blob/main/.env.sample)
and the README's "Local secrets" section) — it's a classic PAT with `repo`
scope, since the default `GITHUB_TOKEN` can't push to a repository's wiki.
