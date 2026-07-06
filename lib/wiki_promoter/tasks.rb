# frozen_string_literal: true

require "fileutils"
require "rake"
require_relative "../wiki_promoter"

namespace :wiki do
  desc "Flatten and relink a docs tree, outputting to tmp/wiki-migration/"
  task :migrate, [:docs_path] do |_t, args|
    docs_path = args[:docs_path] || ENV["DOCS_PATH"]
    raise ArgumentError, "docs_path required (pass as task argument or DOCS_PATH env var)" unless docs_path

    entry_page_name = ENV["ENTRY_PAGE_NAME"]

    migrator = WikiPromoter::Migrator.new(docs_path, entry_page_name: entry_page_name)
    output_dir = ENV["WIKI_OUTPUT_DIR"] || File.join("tmp", "wiki-migration")
    FileUtils.rm_rf(output_dir)
    FileUtils.mkdir_p(output_dir)

    # Write flattened pages
    migrator.pages.each do |filename, content|
      path = File.join(output_dir, filename)
      File.write(path, content)
      puts "  wrote #{path}"
    end

    puts "Migration complete: #{migrator.pages.size} files written to #{output_dir}/"
  end

  desc "Publish docs to wiki, update Home.md, repoint roadmap, and delete source"
  task :publish, [:docs_path] do |_t, args|
    docs_path = args[:docs_path] || ENV["DOCS_PATH"]
    raise ArgumentError, "docs_path required (pass as task argument or DOCS_PATH env var)" unless docs_path

    result = WikiPromoter::Publisher.from_env(docs_path).publish
    puts "Publishing complete: #{result.wiki_url}"
  end
end
