# Dogfood Plan

`wiki_promoter` has never been run against a real target — [GAPS.md](https://github.com/cpb/wiki_promoter/blob/main/GAPS.md)
flags the wiki-branch default (`master` vs `main`) as unverified for exactly
that reason. This PR's tree is meant to be that first real run, against
`cpb/wiki_promoter.wiki` itself.

## Prerequisites checklist

- [ ] **Wiki initialized.** `cpb/wiki_promoter` has the wiki *feature* enabled
      (`has_wiki: true`), but as of this writing `git clone
      https://github.com/cpb/wiki_promoter.wiki.git` returns "Repository not
      found" — GitHub doesn't materialize a wiki git repo until its first
      page is created through the web UI. Someone with write access needs to
      open the **Wiki** tab and create a `Home.md` page (even a one-line
      placeholder) before any push will succeed. `Publisher#add_home_index_entry`
      also expects a `## Settled Decisions` heading in `Home.md` to anchor new
      entries under — worth seeding that in the same first-page edit.
- [ ] **`WIKI_DEPLOY_TOKEN` secret.** A classic PAT with `repo` scope, added
      as a repo secret on `cpb/wiki_promoter` (`gh secret set
      WIKI_DEPLOY_TOKEN --repo cpb/wiki_promoter`). Also drop it in a local
      `.env.local` (see `.env.sample`) if dogfooding from a local checkout
      rather than via the Action.
- [ ] **`WIKI_BRANCH` confirmed.** The publisher defaults to `master`; verify
      which default branch a freshly-initialized `cpb/wiki_promoter.wiki`
      actually uses (GitHub has migrated new repos to `main` by default) and
      pass `WIKI_BRANCH=main` if needed.
- [ ] **This docs tree present in the PR.** Satisfied by this commit —
      `docs/1-rubygems-cicd-and-dogfood/` is the payload to promote.

## Running it

Once the above are true, from this branch:

```bash
WIKI_DEPLOY_TOKEN=… WIKI_REPOSITORY=cpb/wiki_promoter.wiki \
  bundle exec exe/wiki-promoter publish docs/1-rubygems-cicd-and-dogfood
```

(add `WIKI_BRANCH=main` if the clone step reports `master` is missing). This
performs real pushes — the wiki gets these three pages, `Home.md` gets a new
entry under `## Settled Decisions`, and this docs tree is deleted from the
branch in a follow-up commit. It should only be run intentionally, not as
part of routine CI on this PR.

Longer term, once this is proven out, the same promotion can run via the
composite action (`action/action.yml`) triggered on merge, rather than by
hand.
