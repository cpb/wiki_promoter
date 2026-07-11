# AGENTS.md — Developer Orientation

## What this is

`wiki_promoter` is a pure-Ruby gem that automates the promotion of markdown research/planning documents from a hierarchical `docs/` tree into a GitHub Wiki. It includes:

- A Ruby library with the `Migrator` class for flattening and relinking markdown trees
- A CLI tool for command-line invocation
- Reusable Rake tasks for integration into other projects
- A composite GitHub Action for workflow automation

**Current state:** The gem is feature-complete with a full test suite, CLI, and composite action. All core functionality is implemented and working.

## Directory layout

| Path | Purpose |
|---|---|
| `lib/wiki_promoter.rb` | Main gem entrypoint |
| `lib/wiki_promoter/migrator.rb` | Core `Migrator` class for flatten/relink logic |
| `lib/wiki_promoter/publisher.rb` | Portable publish workflow for wiki sync, roadmap repointing, and source cleanup |
| `lib/wiki_promoter/tasks.rb` | Rake tasks for wiki migration/publishing |
| `lib/wiki_promoter/version.rb` | Version constant |
| `exe/wiki-promoter` | CLI executable |
| `action/action.yml` | Composite GitHub Action definition |
| `bin/setup` | Dev environment bootstrapper |
| `bin/test` | Test runner with file:line support |
| `bin/lint` | PostToolUse linting hook (StandardRB only) |
| `bin/console` | Interactive Ruby shell with gem loaded |
| `test/` | Minitest suite with fixtures |
| `test/fixtures/` | Pre-seeded docs/ trees for testing |
| `.standard.yml` | StandardRB configuration (Ruby 3.3) |
| `Gemfile` | Development dependencies |
| `Rakefile` | Rake task runner |
| `wiki_promoter.gemspec` | Gem specification |
| `README.md` | User documentation |
| `CHANGELOG.md` | Version history |
| `LICENSE.txt` | MIT license |

## Build and test commands

- **`bin/setup`** — Installs development dependencies via `bundle install`.
- **`bin/console`** — Opens an interactive IRB session with the gem loaded.
- **`bin/test [file:line]`** — Runs the test suite via `bundle exec rake test`. Supports optional `file:line` argument to run a specific test method.
- **`bin/lint`** — Runs `bundle exec standardrb --fix` on changed files (PostToolUse hook).
- **`bundle exec rake`** — Default task runs: `standard` (lint) → `test` (unit tests).
- **`bundle exec rake test`** — Runs Minitest suite.
- **`bundle exec rake release`** — Creates the `vX.Y.Z` tag and pushes it (does **not** build or push the gem). The pushed tag triggers `release.yml`, which does the build, RubyGems publish, and GitHub Release.

## Core functionality

### Migrator class

Located in `lib/wiki_promoter/migrator.rb`, the `Migrator` class implements:

- **Hierarchical naming**: Converts directory trees into numbered, cased wiki page titles
  - Root level uses issue number: `77`
  - Subdirectories use alphabetic: `a`, `b`, `c`
  - Files use numeric or roman numerals depending on depth: `1`, `2` or `i`, `ii`
  - Example: `77.a.i. Raw Experiment Data`

- **Link rewriting**: Rewrites relative markdown links to reference new wiki page names
  - Input: `[see this](research/data.md)`
  - Output: `[see this](77.a.i. Raw Experiment Data)`
  - Preserves anchors: `[link](file.md#anchor)` → `[link](77.a. Title#anchor)`

- **Title extraction**: Pulls H1 markdown headings (`# Title`) from source files
  - Falls back to filename (with underscores/hyphens → spaces) if no H1
  - Cleans titles: removes unsafe chars (`*`, `:`, `?`, etc.), collapses spaces
  - Truncates long titles to 120 chars with `…`

- **Collision detection**: Raises `CollisionError` if multiple source files would flatten to the same wiki page name

- **Reference repointing**: The module-level `WikiPromoter.repoint_references` method rewrites references to deleted docs trees in files like roadmaps

### Docs tree conventions

Source trees must follow this naming pattern:

```
docs/77-my-research-slug/
├── README.md                 # Becomes "77. My Research Slug"
├── analysis/
│   ├── README.md             # Becomes "77.a. Analysis"
│   ├── data.md               # Becomes "77.a.i. Data"
│   └── conclusions.md        # Becomes "77.a.ii. Conclusions"
└── research/
    ├── README.md             # Becomes "77.b. Research"
    └── findings.md           # Becomes "77.b.i. Findings"
```

The `<issue>` number and `-<slug>` are both required; the issue number is extracted programmatically.

## Testing

- **Unit tests**: `test/migrator_test.rb` — Pure logic tests for flatten/relink behavior
- **Edge case tests**: `test/migrator_edgecases_test.rb` — Title truncation, collision, fallback behavior
- **Fixtures**: `test/fixtures/wiki_migration/` — Pre-seeded real docs tree for regression testing

Run all tests via `bundle exec rake test` (14 tests, ~15ms).

## CLI usage

```bash
wiki-promoter migrate [--output-dir DIR] DOCS_PATH

# Example:
bundle exec exe/wiki-promoter migrate --output-dir /tmp/wiki docs/77-my-research
```

## GitHub Action

The composite action in `action/action.yml` encapsulates the full workflow:

```yaml
- uses: your-org/wiki_promoter/action@v1
  with:
    docs_path: docs/77-spike
    wiki_deploy_token: ${{ secrets.WIKI_DEPLOY_TOKEN }}
    wiki_repository: org/wiki.repo
```

The action:
1. Checks out the repo
2. Sets up Ruby 3.3
3. Installs the gem from the action's local copy
4. Runs migration via CLI
5. Clones the wiki repo
6. Syncs flattened pages to the wiki
7. Pushes cleanup commits back to the PR branch

## Rake tasks

Defined in `lib/wiki_promoter/tasks.rb`:

- **`rake wiki:migrate[docs_path]`** — Flattens and relinks, outputs to `tmp/wiki-migration/`
  - Can also use env var: `DOCS_PATH=docs/77-slug bundle exec rake wiki:migrate`
- **`rake wiki:publish[docs_path]`** — Full workflow: migrates, syncs to the wiki, updates Home.md, repoints roadmap references, removes the source docs tree, and pushes cleanup back to the branch

## Gem release conventions

- **Versioning**: SemVer in `lib/wiki_promoter/version.rb`
- **Current version**: 0.1.0 (initial release)
- **CHANGELOG**: Keep a Changelog format in `CHANGELOG.md`
- **Release workflow**: `.github/workflows/release.yml` triggers on `v*` tags. It creates the GitHub Release **first** (before the gem publish), so the Dependabot invariant — a shipped version always has a Release — holds even if `gem push` fails. The release step is idempotent (`gh release create … || gh release edit …`) so re-runs update rather than hard-fail. Notes are extracted from the matching `## [X.Y.Z]` section of `CHANGELOG.md` (curated, Keep a Changelog), not GitHub's auto-generated PR list. The GitHub Release is required so Dependabot's `github-actions` ecosystem can resolve downstream SHA pins to a version — tags alone are not enough.
- **Local `release` rake task**: Narrowed to tagging only. `bundler/gem_tasks`'s default `release` builds and pushes the `.gem` itself, which would race the tag-triggered CI pipeline. The local task is cleared (guarded by `task_defined?`) and redefined to depend only on `release:guard_clean` and `release:source_control_push` (create the tag and push it); the pushed tag then triggers `release.yml`. So: `bundle exec rake release` tags and pushes — do **not** `gem push` locally. Tradeoff: there is no local emergency gem-publish escape hatch; CI is the only publish path, so cutting a release requires a working `release.yml` run.

## Code comment conventions

Comments explain the **durable why** — invariants, constraints, measured behavior. Avoid narrating PR history; if history matters (empirical results, tradeoffs), link to permanent documentation.

## Keeping this file current

AGENTS.md is the source of truth for how this project is built, tested,
released, and automated. It must stay in sync with reality. When you land a
PR that changes any of the following, include a corresponding AGENTS.md
update in that same PR:

- **Directory layout** — new top-level dirs, moved/renamed files, new entrypoints
- **Build & test commands** — `bin/` scripts, Rakefile tasks, default task composition, test runner changes
- **Core functionality or API** — public methods, CLI flags, Rake task signatures, the composite Action's inputs/outputs
- **Release process** — versioning, the `release.yml` workflow, the local `release` rake task, RubyGems/GitHub Release mechanics
- **CI/CD & automation** — any `.github/workflows/*.yml`, composite Action wiring, Dependabot/secret/permission changes
- **Developer experience (devex)** — local tooling, environment setup (`bin/setup`, `.env.sample`), lint/format config, git hooks, helper scripts
- **Architecture** — gem structure, module boundaries, new top-level classes/modules, data flow between components
- **Dependencies** — meaningful additions/removals/version constraints in `Gemfile`/`wiki_promoter.gemspec` that affect how the project is built or run

If a change spans multiple categories, update every affected section. When in
doubt, update — a stale AGENTS.md is worse than a verbose one. The reviewer
should be able to treat AGENTS.md as authoritative without reading the diff.
