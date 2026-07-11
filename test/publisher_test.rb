# frozen_string_literal: true

require "test_helper"
require "open3"
require "stringio"

class PublisherTest < Minitest::Test
  def write_tree(root, files)
    files.each do |relative_path, content|
      path = File.join(root, relative_path)
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, content)
    end
  end

  def test_migrate_clears_stale_output
    Dir.mktmpdir do |dir|
      tree = File.join(dir, "77-slug")
      output_dir = File.join(dir, "wiki-migration")
      write_tree(tree, {"README.md" => "# Entry\n"})
      FileUtils.mkdir_p(output_dir)
      File.write(File.join(output_dir, "stale.md"), "old")

      publisher = WikiPromoter::Publisher.new(
        docs_path: tree,
        wiki_repository: "example/project",
        wiki_deploy_token: "token",
        output_dir: output_dir
      )
      publisher.migrate

      refute File.exist?(File.join(output_dir, "stale.md"))
      assert File.exist?(File.join(output_dir, "77. Entry.md"))
    end
  end

  def test_entry_url_uses_source_repository_and_wiki_page_name
    Dir.mktmpdir do |dir|
      tree = File.join(dir, "77-slug")
      write_tree(tree, {"README.md" => "# Entry Title\n"})

      publisher = WikiPromoter::Publisher.new(
        docs_path: tree,
        wiki_repository: "example/project.wiki",
        wiki_deploy_token: "token",
        source_repository: "example/project"
      )

      assert_equal "https://github.com/example/project/wiki/77.-Entry-Title", publisher.entry_url
    end
  end

  def test_add_home_index_entry_inserts_before_settled_decisions
    Dir.mktmpdir do |dir|
      tree = File.join(dir, "77-slug")
      output_dir = File.join(dir, "wiki-migration")
      wiki_checkout = File.join(dir, "wiki")
      commands = []
      write_tree(tree, {"README.md" => "# Entry Title\n"})
      FileUtils.mkdir_p(wiki_checkout)
      File.write(File.join(wiki_checkout, "Home.md"), "# Home\n\n## Settled Decisions\n")

      publisher = WikiPromoter::Publisher.new(
        docs_path: tree,
        wiki_repository: "example/project",
        wiki_deploy_token: "token",
        output_dir: output_dir,
        wiki_checkout: wiki_checkout,
        command_runner: ->(cmd) { commands << cmd }
      )
      publisher.migrate
      publisher.send(:add_home_index_entry)

      home = File.read(File.join(wiki_checkout, "Home.md"))
      assert_includes home, "## Issue #77 — Entry Title"
      assert home.index("## Issue #77 — Entry Title") < home.index("## Settled Decisions")
      assert_includes commands, ["git", "-C", wiki_checkout, "add", "Home.md"]
    end
  end

  def test_publish_syncs_wiki_and_pushes_source_cleanup_without_network
    Dir.mktmpdir do |dir|
      source_bare = File.join(dir, "source.git")
      wiki_bare = File.join(dir, "wiki.git")
      source_work = File.join(dir, "source-work")
      wiki_seed = File.join(dir, "wiki-seed")
      wiki_verify = File.join(dir, "wiki-verify")
      source_verify = File.join(dir, "source-verify")

      git("init", "--bare", source_bare, chdir: dir)
      git("init", "--bare", wiki_bare, chdir: dir)

      git("init", "--initial-branch=main", wiki_seed, chdir: dir)
      configure_git(wiki_seed)
      File.write(File.join(wiki_seed, "Home.md"), "# Home\n\n## Settled Decisions\n")
      git("add", ".", chdir: wiki_seed)
      git("commit", "-m", "Seed wiki", chdir: wiki_seed)
      git("remote", "add", "origin", wiki_bare, chdir: wiki_seed)
      git("push", "origin", "main", chdir: wiki_seed)
      git("--git-dir", wiki_bare, "symbolic-ref", "HEAD", "refs/heads/main", chdir: dir)

      git("init", "--initial-branch=feature", source_work, chdir: dir)
      configure_git(source_work)
      write_tree(source_work, {
        "docs/2026-07-01-roadmap.md" => "See [research](docs/77-slug/README.md) and [results](docs/77-slug/research/results.md).\n",
        "docs/77-slug/README.md" => "# Entry Title\n\nSee [research](research/results.md).\n",
        "docs/77-slug/research/results.md" => "# Results Title\n\nFindings.\n"
      })
      git("add", ".", chdir: source_work)
      git("commit", "-m", "Add research docs", chdir: source_work)
      git("remote", "add", "origin", source_bare, chdir: source_work)
      git("push", "-u", "origin", "feature", chdir: source_work)

      Dir.chdir(source_work) do
        result = WikiPromoter::Publisher.new(
          docs_path: "docs/77-slug",
          wiki_repository: "example/project",
          wiki_deploy_token: "token",
          wiki_clone_url: wiki_bare,
          wiki_branch: "main",
          wiki_checkout: File.join(dir, "wiki-checkout"),
          output_dir: File.join(dir, "wiki-migration"),
          source_repository: "example/project",
          branch: "feature"
        ).publish

        assert_equal "https://github.com/example/project/wiki/77.-Entry-Title", result.wiki_url
      end

      git("clone", "--branch", "main", wiki_bare, wiki_verify, chdir: dir)
      entry_page = File.join(wiki_verify, "77. Entry Title.md")
      child_page = File.join(wiki_verify, "77.a.i. Results Title.md")
      assert File.exist?(entry_page)
      assert File.exist?(child_page)
      assert_includes File.read(entry_page), "[Results Title](77.a.i.%20Results%20Title)"
      assert_includes File.read(File.join(wiki_verify, "Home.md")), "## Issue #77 — Entry Title"

      git("clone", "--branch", "feature", source_bare, source_verify, chdir: dir)
      refute Dir.exist?(File.join(source_verify, "docs/77-slug"))
      roadmap = File.read(File.join(source_verify, "docs/2026-07-01-roadmap.md"))
      refute_includes roadmap, "docs/77-slug"
      assert_includes roadmap, "https://github.com/example/project/wiki/77.-Entry-Title"
      # The deep link to the nested results file lands on its own sub-page,
      # not collapsed onto the entry page.
      assert_includes roadmap, "https://github.com/example/project/wiki/77.a.i.-Results-Title"
    end
  end

  def test_publish_copies_assets_to_wiki_repo
    Dir.mktmpdir do |dir|
      source_bare = File.join(dir, "source.git")
      wiki_bare = File.join(dir, "wiki.git")
      source_work = File.join(dir, "source-work")
      wiki_seed = File.join(dir, "wiki-seed")
      wiki_verify = File.join(dir, "wiki-verify")

      git("init", "--bare", source_bare, chdir: dir)
      git("init", "--bare", wiki_bare, chdir: dir)

      git("init", "--initial-branch=main", wiki_seed, chdir: dir)
      configure_git(wiki_seed)
      File.write(File.join(wiki_seed, "Home.md"), "# Home\n\n## Settled Decisions\n")
      git("add", ".", chdir: wiki_seed)
      git("commit", "-m", "Seed wiki", chdir: wiki_seed)
      git("remote", "add", "origin", wiki_bare, chdir: wiki_seed)
      git("push", "origin", "main", chdir: wiki_seed)
      git("--git-dir", wiki_bare, "symbolic-ref", "HEAD", "refs/heads/main", chdir: dir)

      git("init", "--initial-branch=feature", source_work, chdir: dir)
      configure_git(source_work)
      write_tree(source_work, {
        "docs/77-slug/README.md" => "# Entry Title\n\n![diagram](images/arch.png)\n"
      })
      # Write fake PNG bytes in binary mode so round-trip is lossless
      png_bytes = "\x89PNG\r\n".b
      png_path = File.join(source_work, "docs/77-slug/images/arch.png")
      FileUtils.mkdir_p(File.dirname(png_path))
      File.binwrite(png_path, png_bytes)
      git("add", ".", chdir: source_work)
      git("commit", "-m", "Add research with image", chdir: source_work)
      git("remote", "add", "origin", source_bare, chdir: source_work)
      git("push", "-u", "origin", "feature", chdir: source_work)

      Dir.chdir(source_work) do
        WikiPromoter::Publisher.new(
          docs_path: "docs/77-slug",
          wiki_repository: "example/project",
          wiki_deploy_token: "token",
          wiki_clone_url: wiki_bare,
          wiki_branch: "main",
          wiki_checkout: File.join(dir, "wiki-checkout"),
          output_dir: File.join(dir, "wiki-migration"),
          source_repository: "example/project",
          branch: "feature"
        ).publish
      end

      git("clone", "--branch", "main", wiki_bare, wiki_verify, chdir: dir)
      assert File.exist?(File.join(wiki_verify, "77. Entry Title.md")), "wiki entry page missing"
      assert File.exist?(File.join(wiki_verify, "images/arch.png")), "asset not pushed to wiki"
      assert_equal png_bytes, File.binread(File.join(wiki_verify, "images/arch.png"))
    end
  end

  def test_migrate_copies_supported_non_markdown_assets_preserving_hierarchy
    Dir.mktmpdir do |dir|
      tree = File.join(dir, "77-slug")
      output_dir = File.join(dir, "wiki-migration")
      write_tree(tree, {
        "README.md" => "# Entry\n",
        "images/architecture.png" => "fake-image-bytes",
        "docs/report.pdf" => "fake-pdf-bytes"
      })

      publisher = WikiPromoter::Publisher.new(
        docs_path: tree,
        wiki_repository: "example/project",
        wiki_deploy_token: "token",
        output_dir: output_dir
      )
      publisher.migrate

      assert File.exist?(File.join(output_dir, "77. Entry.md"))
      assert File.exist?(File.join(output_dir, "images/architecture.png"))
      assert File.exist?(File.join(output_dir, "docs/report.pdf"))
      assert_equal "fake-image-bytes", File.read(File.join(output_dir, "images/architecture.png"))
      assert_equal "fake-pdf-bytes", File.read(File.join(output_dir, "docs/report.pdf"))
    end
  end

  def test_migrate_halts_on_unsupported_assets
    Dir.mktmpdir do |dir|
      tree = File.join(dir, "77-slug")
      output_dir = File.join(dir, "wiki-migration")
      write_tree(tree, {
        "README.md" => "# Entry\n",
        "malicious.exe" => "fake-binary-bytes"
      })

      publisher = WikiPromoter::Publisher.new(
        docs_path: tree,
        wiki_repository: "example/project",
        wiki_deploy_token: "token",
        output_dir: output_dir,
        interactive: false
      )

      assert_raises(WikiPromoter::Error) do
        # Non-interactive and not forced: must raise rather than prompt.
        publisher.migrate
      end
    end
  end

  def test_migrate_prompts_and_proceeds_when_interactive_user_confirms
    Dir.mktmpdir do |dir|
      tree = File.join(dir, "77-slug")
      output_dir = File.join(dir, "wiki-migration")
      write_tree(tree, {"README.md" => "# Entry\n", "malicious.exe" => "bytes"})

      publisher = WikiPromoter::Publisher.new(
        docs_path: tree,
        wiki_repository: "example/project",
        wiki_deploy_token: "token",
        output_dir: output_dir,
        interactive: true,
        input: StringIO.new("y\n"),
        output: StringIO.new
      )
      publisher.migrate

      assert File.exist?(File.join(output_dir, "malicious.exe"))
    end
  end

  def test_migrate_prompts_and_aborts_when_interactive_user_declines
    Dir.mktmpdir do |dir|
      tree = File.join(dir, "77-slug")
      output_dir = File.join(dir, "wiki-migration")
      write_tree(tree, {"README.md" => "# Entry\n", "malicious.exe" => "bytes"})

      publisher = WikiPromoter::Publisher.new(
        docs_path: tree,
        wiki_repository: "example/project",
        wiki_deploy_token: "token",
        output_dir: output_dir,
        interactive: true,
        input: StringIO.new("n\n"),
        output: StringIO.new
      )

      assert_raises(WikiPromoter::Error) { publisher.migrate }
    end
  end

  def test_migrate_proceeds_on_unsupported_assets_if_forced
    Dir.mktmpdir do |dir|
      tree = File.join(dir, "77-slug")
      output_dir = File.join(dir, "wiki-migration")
      write_tree(tree, {
        "README.md" => "# Entry\n",
        "malicious.exe" => "fake-binary-bytes"
      })

      publisher = WikiPromoter::Publisher.new(
        docs_path: tree,
        wiki_repository: "example/project",
        wiki_deploy_token: "token",
        output_dir: output_dir,
        force: true
      )
      publisher.migrate

      assert File.exist?(File.join(output_dir, "77. Entry.md"))
      assert File.exist?(File.join(output_dir, "malicious.exe"))
      assert_equal "fake-binary-bytes", File.read(File.join(output_dir, "malicious.exe"))
    end
  end

  def configure_git(path)
    git("config", "user.name", "Test User", chdir: path)
    git("config", "user.email", "test@example.com", chdir: path)
    git("config", "commit.gpgsign", "false", chdir: path)
    git("config", "tag.gpgsign", "false", chdir: path)
  end

  def git(*args, chdir:)
    stdout, stderr, status = Open3.capture3("git", *args, chdir: chdir)
    assert status.success?, "git #{args.join(" ")} failed in #{chdir}\nSTDOUT:\n#{stdout}\nSTDERR:\n#{stderr}"

    stdout
  end
end
