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

## Code comment conventions

Comments explain the **durable why** — invariants, constraints, measured behavior. Avoid narrating PR history; if history matters (empirical results, tradeoffs), link to permanent documentation.

## Keeping this file current

When you land a PR that changes:

- Directory layout (new top-level dirs, moved files)
- Build/test commands (`bin/` scripts, Rakefile tasks)
- Core functionality or API
- Release process

Propose an update to AGENTS.md as part of that PR so this stays in sync with reality.
