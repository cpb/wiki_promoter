# frozen_string_literal: true

require "bundler/gem_tasks"
require "rake/testtask"

ENV["RUBOCOP_CACHE_ROOT"] ||= File.join("tmp", "rubocop_cache")

require "standard/rake"

task default: %i[standard test]

Rake::TestTask.new(:test) do |t|
  t.libs = ["lib", "test"]
  t.pattern = "test/**/*_test.rb"
  t.verbose = true
end

# Load custom rake tasks (wiki:migrate, wiki:publish, etc.)
load "lib/wiki_promoter/tasks.rb" if File.exist?("lib/wiki_promoter/tasks.rb")
