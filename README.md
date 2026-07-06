# GitHub Wiki Research PR

A pure-Ruby gem for mechanized promotion of markdown research/planning documents from a `docs/` hierarchy into a GitHub Wiki. Includes a CLI tool and composite GitHub Action.

## Features

- **Hierarchical page naming**: Automatically generates numbered, cased wiki page titles from directory structure
- **Link rewriting**: Rewrites relative links to reference new wiki page names
- **Collision detection**: Detects and reports when multiple source files would flatten to the same wiki page
- **Roadmap reference repointing**: Targeted literal replacement for updating roadmap doc references after source deletion
- **Pure Ruby**: No native extensions, no external dependencies
- **CLI & Rake tasks**: Exposes both a command-line tool and reusable Rake tasks

## Installation

Add to your `Gemfile`:

```ruby
gem "wiki_promoter"
```

Then run:

```bash
bundle install
```

## Usage

### CLI

```bash
wiki-promoter migrate --output-dir /tmp/wiki docs/77-your-research-tree
```

This flattens and relinks the docs tree into GitHub Wiki format, outputting to the specified directory.

### Rake Tasks

Add to your `Rakefile`:

```ruby
require "wiki_promoter/tasks"
```

Then use:

```bash
bundle exec rake wiki:migrate[docs/77-your-tree]
bundle exec rake wiki:publish[docs/77-your-tree]
```

`wiki:publish` expects `WIKI_DEPLOY_TOKEN` and `WIKI_REPOSITORY` (for example,
`your-org/your-repo.wiki`). Optional environment variables include
`ROADMAP_PATH`, `UPDATE_HOME_PAGE`, `SOURCE_REPOSITORY`, `WIKI_FORCE`,
`WIKI_BRANCH`, `WIKI_OUTPUT_DIR`, and `WIKI_CHECKOUT_DIR`.

### Ruby API

```ruby
require "wiki_promoter"

migrator = WikiPromoter::Migrator.new("docs/77-your-tree")
pages = migrator.pages  # => {"77. Title.md" => "content", ...}
```

## Development

### Setup

```bash
bin/setup
```

### Running Tests

```bash
bundle exec rake test
```

### Running Linter

```bash
bundle exec standardrb
```

### Fixing Linter Issues

```bash
bundle exec standardrb --fix
```

## Docs Structure Conventions

The gem expects `docs/` trees to follow this naming pattern:

```
docs/
├── 77-issue-slug/           # Issue number required, slug auto-becomes entry page name
│   ├── README.md            # Becomes "77. ..."
│   ├── research/
│   │   ├── README.md        # Becomes "77.a. ..."
│   │   ├── data.md          # Becomes "77.a.i. ..."
│   │   └── ...
│   ├── analysis/
│   │   ├── README.md        # Becomes "77.b. ..."
│   │   └── ...
│   └── ...
```

**Numbering rules:**
- Root level: Issue number (e.g., `77`)
- Subdirectories: Alphabetic (`a`, `b`, `c`, ...)
- Files in each dir: Numeric (`1`, `2`, `3`, ...) or Roman (`i`, `ii`, `iii`, ...) depending on depth

**Page titles:**
- Extracted from H1 markdown headings (`# Title`)
- Unsafe characters (`*`, `:`, `?`, etc.) stripped
- Consecutive spaces collapsed
- Long titles truncated to 120 characters with `…`

## GitHub Action

The `action/` directory defines a composite GitHub Action that runs the migration workflow end-to-end: flatten pages, sync the wiki, optionally update `Home.md`, repoint roadmap references, remove the source docs tree, and push the cleanup commit back to the branch.

```yaml
- uses: your-org/wiki_promoter/action@v1
  with:
    docs_path: docs/77-spike-slug
    wiki_deploy_token: ${{ secrets.WIKI_DEPLOY_TOKEN }}
    wiki_repository: your-org/your-repo.wiki
    roadmap_path: docs/2026-07-01-roadmap.md
```

## License

MIT
