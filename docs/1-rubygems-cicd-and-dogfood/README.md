# RubyGems CI/CD Setup & Wiki Promotion Dogfood

Tracks issue [#1](https://github.com/cpb/wiki_promoter/issues/1): wire up
tag-triggered publishing to RubyGems, document the secrets a contributor
needs, and use this PR's own research tree as the first real-world run of
`wiki_promoter`'s publish action against `cpb/wiki_promoter.wiki`.

This tree is itself the dogfood payload — once this PR settles, running
`wiki-promoter publish docs/1-rubygems-cicd-and-dogfood` (or the composite
action) against this repo should flatten these pages onto the wiki and
delete this tree from `main`, exactly the workflow the gem exists to
automate.

- [Setup: RubyGems release flow](setup/README.md) — one-time account/secret
  setup and the steps to cut a release.
- [Dogfood plan](dogfood/README.md) — what has to be true before we can
  safely run wiki promotion against this repo.
