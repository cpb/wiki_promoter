# frozen_string_literal: true

begin
  require "dotenv"
  Dotenv.load(".env.local")
rescue LoadError
end

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

# bundler/gem_tasks's default `release` task builds and pushes the .gem
# itself, which would race the tag-triggered CI pipeline in
# .github/workflows/release.yml that already does the actual build and
# publish once a vX.Y.Z tag lands. Narrow `release` to just tagging.
Rake::Task["release"].clear
task release: ["release:guard_clean", "release:source_control_push"]
