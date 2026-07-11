# How the Workflow Works

The `.github/workflows/promote-wiki.yml` workflow in this PR uses the
composite action at `./action`:

1. **Checkout** the repo (the branch that triggered the workflow).
2. **Set up Ruby** 3.3.
3. **Run the composite action** which:
   - Loads the gem from `${{ github.action_path }}/..` (the repo root).
   - Runs `exe/wiki-promoter publish docs/3-action-dogfood`.
   - The publisher migrates the docs tree, clones the wiki, copies pages,
     updates `Home.md`, pushes the wiki, then `git rm`s the source tree
     and pushes a cleanup commit back to the branch.
4. **Comment on the PR** with a link to the migrated wiki page.

The `WIKI_DEPLOY_TOKEN` secret (classic PAT with `repo` scope) is passed
to the action. The default `GITHUB_TOKEN` is used for the source-branch
cleanup push.
