# Gaps and Remediation Notes

Open follow-ups for the extracted `wiki_promoter` gem. Everything from
the initial extraction and the 2026-07-05 adversarial review is fixed; the suite
passes at 33 runs / 184 assertions with StandardRB clean.

## Remaining follow-ups

- **Verify the wiki branch default against a real target.** (decided: live check)
  - The publisher defaults `WIKI_BRANCH` to `master` (overridable via
    `WIKI_BRANCH`); newer wikis may default to `main`.
  - Decision: confirm with a real migration rather than more code. This performs
    real pushes (wiki + source branch) and a `git rm` of the docs tree, so it
    must run against the intended target (e.g. the duckling PR #82 branch) or a
    throwaway repo — not a dry run.
  - Command (from a checkout of the target repo, on the PR branch):
    `WIKI_DEPLOY_TOKEN=… bundle exec exe/wiki-promoter publish docs/<issue>-slug`
    or via the Rake task `wiki:publish[docs/<issue>-slug]`. Add `WIKI_BRANCH=main`
    if the clone/reset step reports `master` is missing.
  - Status: blocked on choosing the target repo; `WIKI_DEPLOY_TOKEN` and `gh`
    auth are present in this environment.

- **Live end-to-end test of the composite action via `act`.** (decided: local act)
  - `test/action_test.rb` statically proves the action's include/exe paths
    resolve; nothing exercises the real checkout + Ruby setup + publish path.
  - Decision: run once locally with `nektos/act` (installed), no committed CI job.
  - Command: `act workflow_dispatch -j <job> --input docs_path=<path> -s WIKI_DEPLOY_TOKEN=…`
    against a workflow that invokes `./action` with a fixture docs tree.
  - Status: blocked — Docker daemon is not running, and because the action always
    performs a real publish it must target a throwaway repo/wiki, not a live one.

## Done in this pass (kept for reference until verified live)

- Internal anchor links are now re-slugified to GitHub's heading-anchor rules
  (`Migrator#slugify_anchor`: downcase, drop punctuation, spaces→hyphens;
  idempotent on correct slugs), so loosely written fragments still resolve after
  flattening. Covered by a migrator unit test.
