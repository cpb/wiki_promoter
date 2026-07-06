# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2026-07-05

### Added

- Initial release of `wiki_promoter` gem
- Core `Migrator` class for flattening and relinking markdown research trees
- Hierarchical page naming with alphabetic, roman, and numeric numbering
- Link rewriting to reference new wiki page names
- Collision detection for duplicate page names
- `repoint_references` method for updating roadmap references
- CLI executable: `wiki-promoter migrate`
- Rake tasks: `wiki:migrate` and `wiki:publish`
- Portable publisher implementation for wiki sync, Home index updates, roadmap repointing, and source cleanup
- Composite action wired through the shared CLI publish workflow
- Comprehensive unit and edge-case tests
- Composite GitHub Action wrapper in `action/action.yml`
