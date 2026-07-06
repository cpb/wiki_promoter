# frozen_string_literal: true

require_relative "lib/wiki_promoter/version"

Gem::Specification.new do |spec|
  spec.name = "wiki_promoter"
  spec.version = WikiPromoter::VERSION
  spec.authors = ["CPB"]
  spec.email = ["cpb@github.com"]

  spec.summary = "Flatten, migrate, and sync GitHub Markdown research trees to GitHub Wiki"
  spec.description = "A pure-Ruby gem that automates promoting research/planning documents from a docs/ hierarchy into a GitHub Wiki. Includes Rake tasks for local use and a composite GitHub Action for workflow automation."
  spec.homepage = "https://github.com/cpb/wiki_promoter"
  spec.license = "MIT"

  spec.files = Dir.glob(%w[
    README.md
    LICENSE.txt
    CHANGELOG.md
    lib/**/*
    exe/**/*
    action/action.yml
  ]).reject { |f| File.directory?(f) }

  spec.bindir = "exe"
  spec.executables = ["wiki-promoter"]

  spec.required_ruby_version = ">= 3.3.0"

  spec.add_development_dependency "standard", "~> 1.0"
  spec.add_development_dependency "minitest", "~> 5.0"
  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "dotenv", "~> 2.8"
end
