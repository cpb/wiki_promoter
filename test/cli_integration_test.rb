# frozen_string_literal: true

require "test_helper"
require "open3"

class CliIntegrationTest < Minitest::Test
  def write_tree(root, files)
    files.each do |relative_path, content|
      path = File.join(root, relative_path)
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, content)
    end
  end

  def test_cli_migrate_command
    Dir.mktmpdir do |dir|
      docs_path = File.join(dir, "81-pr-docs")
      output_dir = File.join(dir, "wiki-migration-out")

      write_tree(docs_path, {
        "README.md" => "# Main Title\nLink to [research](research/findings.md)\n",
        "research/README.md" => "# Research Section\n",
        "research/findings.md" => "# Research Findings\n"
      })

      # Run the CLI migrate command
      cli_path = File.expand_path("../exe/wiki-promoter", __dir__)
      stdout, stderr, status = Open3.capture3(
        Gem.ruby,
        cli_path,
        "migrate",
        "--output-dir", output_dir,
        docs_path
      )

      assert status.success?, "CLI failed with: #{stderr}"
      assert_includes stdout, "Migration complete"

      expected_files = [
        "81. Main Title.md",
        "81.a. Research Section.md",
        "81.a.i. Research Findings.md"
      ]

      expected_files.each do |filename|
        assert File.exist?(File.join(output_dir, filename)), "Expected file #{filename} to exist"
      end

      # Verify link rewriting in the migrated file
      main_content = File.read(File.join(output_dir, "81. Main Title.md"))
      assert_includes main_content, "Link to [Research Findings](81.a.i.%20Research%20Findings)"
    end
  end

  def test_cli_publish_command
    Dir.mktmpdir do |dir|
      source_bare = File.join(dir, "source.git")
      wiki_bare = File.join(dir, "wiki.git")
      source_work = File.join(dir, "source-work")
      wiki_seed = File.join(dir, "wiki-seed")

      # Init bare repos
      git("init", "--bare", source_bare)
      git("init", "--bare", wiki_bare)

      # Seed wiki
      git("init", "--initial-branch=main", wiki_seed)
      configure_git(wiki_seed)
      File.write(File.join(wiki_seed, "Home.md"), "# Home\n\n## Settled Decisions\n")
      git("add", ".", chdir: wiki_seed)
      git("commit", "-m", "Seed wiki", chdir: wiki_seed)
      git("remote", "add", "origin", wiki_bare, chdir: wiki_seed)
      git("push", "origin", "main", chdir: wiki_seed)
      git("--git-dir", wiki_bare, "symbolic-ref", "HEAD", "refs/heads/main")

      # Setup source repo worktree
      git("init", "--initial-branch=feature", source_work)
      configure_git(source_work)
      write_tree(source_work, {
        "docs/2026-07-01-roadmap.md" => "See [research](docs/77-slug/README.md).\n",
        "docs/77-slug/README.md" => "# Entry Title\n\nSee [research](research/results.md).\n",
        "docs/77-slug/research/results.md" => "# Results Title\n\nFindings.\n"
      })
      git("add", ".", chdir: source_work)
      git("commit", "-m", "Add research docs", chdir: source_work)
      git("remote", "add", "origin", source_bare, chdir: source_work)
      git("push", "-u", "origin", "feature", chdir: source_work)

      cli_path = File.expand_path("../exe/wiki-promoter", __dir__)

      # Run CLI publish command
      Dir.chdir(source_work) do
        # Use env overrides like in the action/unit tests
        env = {
          "WIKI_REPOSITORY" => "example/project",
          "WIKI_DEPLOY_TOKEN" => "token",
          "WIKI_CLONE_URL" => wiki_bare,
          "WIKI_BRANCH" => "main",
          "WIKI_CHECKOUT_DIR" => File.join(dir, "wiki-checkout"),
          "WIKI_OUTPUT_DIR" => File.join(dir, "wiki-migration"),
          "SOURCE_REPOSITORY" => "example/project",
          "GITHUB_REF_NAME" => "feature"
        }

        stdout, stderr, status = Open3.capture3(
          env,
          Gem.ruby,
          cli_path,
          "publish",
          "docs/77-slug"
        )

        assert status.success?, "CLI publish failed with:\nSTDOUT:\n#{stdout}\nSTDERR:\n#{stderr}"
        assert_includes stdout, "Publishing complete:"
      end

      # Verify wiki got updated
      wiki_verify = File.join(dir, "wiki-verify")
      git("clone", "--branch", "main", wiki_bare, wiki_verify)
      assert File.exist?(File.join(wiki_verify, "77. Entry Title.md"))
      assert File.exist?(File.join(wiki_verify, "77.a.i. Results Title.md"))
    end
  end

  private

  def configure_git(path)
    git("config", "user.name", "Test User", chdir: path)
    git("config", "user.email", "test@example.com", chdir: path)
    git("config", "commit.gpgsign", "false", chdir: path)
    git("config", "tag.gpgsign", "false", chdir: path)
  end

  def git(*args, chdir: nil)
    opts = {}
    opts[:chdir] = chdir if chdir
    stdout, stderr, status = Open3.capture3("git", *args, opts)
    assert status.success?, "git #{args.join(" ")} failed in #{chdir || Dir.pwd}\nSTDOUT:\n#{stdout}\nSTDERR:\n#{stderr}"
    stdout
  end
end
