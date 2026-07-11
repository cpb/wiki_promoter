# Wiki Promotion via GitHub Action

Tracks issue [#3](https://github.com/cpb/wiki_promoter/issues/3): verify
the composite GitHub Action end-to-end by promoting this very docs tree to
`cpb/wiki_promoter.wiki` via a workflow, not the local rake task.

This is the second dogfood run. The first (PR #2) used `rake wiki:publish`
locally. This one uses the `action/action.yml` composite action inside a
GitHub Actions workflow to prove the full CI path works: checkout, Ruby
setup, gem load via `action_path`, migrate, wiki push, and source cleanup.

