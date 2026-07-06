# frozen_string_literal: true

require "test_helper"

# These tests exercise WikiPromoter::Migrator's pure flatten/relink logic
# against fixture trees -- they never touch git/gh or the real wiki repo.
# One fixture is a frozen copy of PR #81's actual docs tree, so
# the flatten/relink rules are verified against real content, not just
# synthetic paths.
class MigratorTest < Minitest::Test
  FIXTURES_DIR = File.expand_path("fixtures/wiki_migration", __dir__)
  PR81_TREE = File.join(FIXTURES_DIR, "77-spike-does-rb-nogvl-offload-safe-obviate-thread-wrapper")

  def write_tree(root, files)
    files.each do |relative_path, content|
      path = File.join(root, relative_path)
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, content)
    end
  end

  def test_entry_page_name_defaults_to_slug_verbatim
    migrator = WikiPromoter::Migrator.new("docs/77-spike-does-rb-nogvl-offload-safe-obviate-thread-wrapper")
    assert_equal "spike-does-rb-nogvl-offload-safe-obviate-thread-wrapper", migrator.entry_page_name
  end

  def test_entry_page_name_override_wins
    migrator = WikiPromoter::Migrator.new("docs/77-slug", entry_page_name: "custom-name")
    assert_equal "custom-name", migrator.entry_page_name
  end

  def test_rejects_a_path_without_a_leading_issue_number
    assert_raises(ArgumentError) { WikiPromoter::Migrator.new("docs/not-numbered") }
  end

  def test_wiki_names_hierarchical_rules
    migrator = WikiPromoter::Migrator.new(PR81_TREE)
    names = migrator.wiki_names

    assert_equal "77. Spike does rb_nogvl + RB_NOGVL_OFFLOAD_SAFE obviate the Thread wrapper", names["README.md"]
    assert_equal "77.a. Research rb_nogvl + RB_NOGVL_OFFLOAD_SAFE mechanism spike", names["research/README.md"]
    assert_equal "77.a.i. Raw experiment data", names["research/results.md"]
  end

  def test_h1_extracts_first_heading_only
    migrator = WikiPromoter::Migrator.new("docs/1-slug")
    content = "intro text\n# Real Title\nmore text\n# Not This One\n"
    assert_equal "Real Title", migrator.h1(content)
  end

  def test_pages_rewrites_internal_links_with_target_h1_as_text
    Dir.mktmpdir do |dir|
      tree = File.join(dir, "77-slug")
      write_tree(tree, {
        "README.md" => "# Entry Title\n\nSee [research/README.md](research/README.md) and [results](research/results.md#raw-data).\n",
        "research/README.md" => "# Research Title\n\nSee [results.md](results.md).\n",
        "research/results.md" => "# Results Title\n\nNo links here.\n"
      })

      pages = WikiPromoter::Migrator.new(tree, entry_page_name: "entry").pages

      assert_equal [
        "77. Entry Title.md",
        "77.a. Research Title.md",
        "77.a.i. Results Title.md"
      ].sort, pages.keys.sort

      assert_includes pages.fetch("77. Entry Title.md"), "[Research Title](77.a. Research Title)"
      assert_includes pages.fetch("77. Entry Title.md"), "[Results Title](77.a.i. Results Title#raw-data)"
      assert_includes pages.fetch("77.a. Research Title.md"), "[Results Title](77.a.i. Results Title)"
    end
  end

  def test_pages_slugifies_loosely_written_anchors_to_github_rules
    Dir.mktmpdir do |dir|
      tree = File.join(dir, "77-slug")
      write_tree(tree, {
        "README.md" => "# Entry Title\n\nSee [results](results.md#Section-1.2).\n",
        "results.md" => "# Results Title\n\n## Section 1.2\n"
      })

      pages = WikiPromoter::Migrator.new(tree, entry_page_name: "entry").pages

      # Author wrote "#Section-1.2"; GitHub's heading anchor for "## Section 1.2"
      # is "section-12" (downcased, dot dropped). The slugifier reconciles them.
      assert_includes pages.fetch("77. Entry Title.md"), "[Results Title](77.1. Results Title#section-12)"
    end
  end

  def test_pages_leaves_external_links_and_code_fences_untouched
    Dir.mktmpdir do |dir|
      tree = File.join(dir, "1-slug")
      write_tree(tree, {
        "README.md" => <<~MD
          # Entry Title

          External: [duckling](https://github.com/wafer-inc/duckling).

          ```
          [fake link](other.md)
          ```
        MD
      })

      content = WikiPromoter::Migrator.new(tree, entry_page_name: "entry").pages.fetch("1. Entry Title.md")
      assert_includes content, "[duckling](https://github.com/wafer-inc/duckling)"
      assert_includes content, "[fake link](other.md)"
    end
  end

  def test_check_collisions_raises_when_two_sources_flatten_to_the_same_name
    Dir.mktmpdir do |dir|
      tree = File.join(dir, "1-slug")
      write_tree(tree, {
        "README.md" => "# Entry\n",
        "file1.md" => "# Duplicate H1\n",
        "file2.md" => "# Duplicate H1\n"
      })

      migrator = WikiPromoter::Migrator.new(tree, entry_page_name: "entry")
      migrator.define_singleton_method(:wiki_names) do
        {"file1.md" => "duplicate", "file2.md" => "duplicate"}
      end

      error = assert_raises(WikiPromoter::Migrator::CollisionError) do
        migrator.pages
      end
      assert_match(/duplicate/, error.message)
    end
  end

  def test_repoint_references_replaces_relative_path_and_blob_permalink
    content = <<~MD
      See [research-ffi-risks](docs/1-slug/research/ffi-risks.md) and
      [background](https://github.com/cpb/duckling/blob/main/docs/1-slug/README.md#background).
    MD

    updated = WikiPromoter.repoint_references(
      content,
      docs_path: "docs/1-slug",
      entry_url: "https://github.com/cpb/duckling/wiki/entry",
      repository: "cpb/duckling"
    )

    refute_includes updated, "docs/1-slug"
    assert_equal 2, updated.scan("https://github.com/cpb/duckling/wiki/entry").size
  end

  def test_repoint_references_leaves_unrelated_content_untouched
    content = "See [the roadmap](https://github.com/cpb/duckling/blob/main/docs/2026-07-01-roadmap.md).\n"
    updated = WikiPromoter.repoint_references(
      content,
      docs_path: "docs/1-slug",
      entry_url: "https://github.com/cpb/duckling/wiki/entry",
      repository: "cpb/duckling"
    )
    assert_equal content, updated
  end

  def test_repoint_references_repoints_deep_links_to_their_own_subpage
    content = <<~MD
      See [entry](docs/1-slug/README.md) and
      [results](docs/1-slug/research/results.md#background) for detail.
    MD

    updated = WikiPromoter.repoint_references(
      content,
      docs_path: "docs/1-slug",
      entry_url: "https://github.com/cpb/duckling/wiki/1.-Entry",
      repository: "cpb/duckling",
      page_urls: {
        "docs/1-slug/README.md" => "https://github.com/cpb/duckling/wiki/1.-Entry",
        "docs/1-slug/research/results.md" => "https://github.com/cpb/duckling/wiki/1.a.i.-Results"
      }
    )

    refute_includes updated, "docs/1-slug"
    assert_includes updated, "https://github.com/cpb/duckling/wiki/1.-Entry"
    # The nested file lands on its own sub-page, not the entry page.
    assert_includes updated, "https://github.com/cpb/duckling/wiki/1.a.i.-Results"
  end

  def test_repoint_references_honors_a_custom_github_host
    content = "See [entry](docs/1-slug/README.md) and https://ghe.example.com/org/repo/blob/main/docs/1-slug/README.md\n"
    updated = WikiPromoter.repoint_references(
      content,
      docs_path: "docs/1-slug",
      entry_url: "https://ghe.example.com/org/repo/wiki/1.-Entry",
      repository: "org/repo",
      github_host: "https://ghe.example.com"
    )
    refute_includes updated, "docs/1-slug"
    assert_equal 2, updated.scan("https://ghe.example.com/org/repo/wiki/1.-Entry").size
  end

  def test_check_collisions_is_case_insensitive
    Dir.mktmpdir do |dir|
      tree = File.join(dir, "1-slug")
      write_tree(tree, {"README.md" => "# Entry\n"})

      migrator = WikiPromoter::Migrator.new(tree)
      migrator.define_singleton_method(:wiki_names) do
        {"a.md" => "1.1. Appendix", "b.md" => "1.1. appendix"}
      end

      assert_raises(WikiPromoter::Migrator::CollisionError) { migrator.pages }
    end
  end

  def test_entry_wiki_name_raises_without_a_root_readme
    Dir.mktmpdir do |dir|
      tree = File.join(dir, "1-slug")
      write_tree(tree, {"notes.md" => "# Notes\n"})

      migrator = WikiPromoter::Migrator.new(tree)
      error = assert_raises(ArgumentError) { migrator.entry_wiki_name }
      assert_match(/README\.md/, error.message)
    end
  end

  def test_pages_against_real_pr81_docs_tree
    migrator = WikiPromoter::Migrator.new(PR81_TREE)
    pages = migrator.pages

    assert_equal "spike-does-rb-nogvl-offload-safe-obviate-thread-wrapper", migrator.entry_page_name
    assert_equal [
      "77. Spike does rb_nogvl + RB_NOGVL_OFFLOAD_SAFE obviate the Thread wrapper.md",
      "77.a. Research rb_nogvl + RB_NOGVL_OFFLOAD_SAFE mechanism spike.md",
      "77.a.i. Raw experiment data.md"
    ].sort, pages.keys.sort

    entry = pages.fetch("77. Spike does rb_nogvl + RB_NOGVL_OFFLOAD_SAFE obviate the Thread wrapper.md")
    assert_includes entry, "[Research: `rb_nogvl` + `RB_NOGVL_OFFLOAD_SAFE` mechanism spike](77.a. Research rb_nogvl + RB_NOGVL_OFFLOAD_SAFE mechanism spike)"
    assert_includes entry, "[Raw experiment data](77.a.i. Raw experiment data)"
    assert_includes entry, "[Research: `rb_nogvl` + `RB_NOGVL_OFFLOAD_SAFE` mechanism spike](77.a. Research rb_nogvl + RB_NOGVL_OFFLOAD_SAFE mechanism spike#two-track-methodology)"
    # External permalinks must survive untouched
    assert_includes entry, "https://github.com/cpb/duckling/blob/main/ext/duckling/src/lib.rs"
    assert_includes entry, "https://github.com/cpb/duckling/wiki/research-async-reactor-blocking"

    research = pages.fetch("77.a. Research rb_nogvl + RB_NOGVL_OFFLOAD_SAFE mechanism spike.md")
    assert_includes research, "[Raw experiment data](77.a.i. Raw experiment data)"
  end
end
