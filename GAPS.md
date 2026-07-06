# Gaps and Remediation Notes

Open follow-ups for the `wiki_promoter` gem. The initial extraction, the
2026-07-05 adversarial review, the anchor slugifier, and a live `act` run of the
composite action are all done; the suite passes at 34 runs / 186 assertions with
StandardRB clean.

## Remaining follow-ups

- **Verify the wiki branch default against a real target.**
  - The publisher defaults `WIKI_BRANCH` to `master` (overridable via
    `WIKI_BRANCH`); newer wikis may default to `main`, which would fail the
    clone/reset until overridden.
  - This performs real pushes (wiki + source branch) and a `git rm` of the docs
    tree, so it must run against the intended target (e.g. the duckling PR #82
    branch) or a throwaway repo — not a dry run.
  - Command (from a checkout of the target repo, on the PR branch):
    `WIKI_DEPLOY_TOKEN=… bundle exec exe/wiki-promoter publish docs/<issue>-slug`
    (add `WIKI_BRANCH=main` if the clone reports `master` is missing).
  - Status: blocked on choosing the target repo.

## Verified this pass

- **Composite action, live via `act`** (2026-07-05): a local `act` run against a
  fixture tree and a throwaway wiki confirmed the action loads, checks out, sets
  up Ruby, loads the gem via `${{ github.action_path }}/../lib`, dispatches the
  `wiki-promoter` CLI, and flattens the tree — then halts safely at the wiki
  clone (dummy token) before any real push. It caught a real bug: a `${{ }}`
  expression in an input description made the whole action fail to load
  ("expressions are not allowed here"). Fixed, with a `test/action_test.rb`
  guard (`test_inputs_contain_no_disallowed_expressions`) so it can't regress.
- **Anchor slugification**: internal-link `#fragments` are normalized to
  GitHub's heading-anchor rules (`Migrator#slugify_anchor`), covered by a unit
  test.
