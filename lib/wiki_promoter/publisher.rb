# frozen_string_literal: true

require "fileutils"
require "open3"

module WikiPromoter
  class Publisher
    SUPPORTED_EXTENSIONS = %w[.png .jpg .jpeg .gif .svg .webp .ico .pdf .txt .csv .tsv .json .jsonld .xml .yml .yaml].freeze

    PublishResult = Struct.new(:wiki_url, :pages) do
      def initialize(wiki_url:, pages:)
        super(wiki_url, pages)
      end
    end

    attr_reader :docs_path, :entry_url, :migrator, :output_dir, :wiki_checkout

    def initialize(
      docs_path:,
      wiki_repository: nil,
      wiki_deploy_token: nil,
      output_dir: File.join("tmp", "wiki-migration"),
      wiki_checkout: File.join("tmp", "wiki-checkout"),
      roadmap_path: "docs/2026-07-01-roadmap.md",
      update_home_page: true,
      source_repository: nil,
      wiki_clone_url: nil,
      wiki_branch: "master",
      force: false,
      branch: nil,
      entry_page_name: nil,
      github_host: "https://github.com",
      git_user_name: "github-actions[bot]",
      git_user_email: "github-actions[bot]@users.noreply.github.com",
      command_runner: nil,
      capture_runner: nil,
      input: $stdin,
      output: $stdout,
      interactive: nil
    )
      @docs_path = docs_path
      @wiki_repository = wiki_repository ? normalize_wiki_repository(wiki_repository) : nil
      @wiki_deploy_token = wiki_deploy_token
      @output_dir = output_dir
      @wiki_checkout = wiki_checkout
      @roadmap_path = roadmap_path
      @update_home_page = update_home_page
      @source_repository = source_repository || (wiki_repository ? source_repository_from_wiki : nil)
      @wiki_clone_url = wiki_clone_url
      @wiki_branch = wiki_branch
      @force = force
      @branch = branch
      @github_host = (github_host.nil? || github_host.to_s.strip.empty?) ? "https://github.com" : github_host.to_s.sub(%r{/+\z}, "")
      @git_user_name = git_user_name
      @git_user_email = git_user_email
      @command_runner = command_runner
      @capture_runner = capture_runner
      @input = input
      @output = output
      @interactive = interactive
      @migrator = Migrator.new(docs_path, entry_page_name: entry_page_name)
      @entry_url = @source_repository ? build_entry_url : nil
    end

    def self.from_env(docs_path)
      new(
        docs_path: docs_path,
        wiki_repository: ENV["WIKI_REPOSITORY"] || ENV["WIKI_REPO"],
        wiki_deploy_token: ENV["WIKI_DEPLOY_TOKEN"],
        output_dir: ENV["WIKI_OUTPUT_DIR"] || File.join("tmp", "wiki-migration"),
        wiki_checkout: ENV["WIKI_CHECKOUT_DIR"] || File.join("tmp", "wiki-checkout"),
        roadmap_path: ENV["ROADMAP_PATH"] || "docs/2026-07-01-roadmap.md",
        update_home_page: truthy_env?("UPDATE_HOME_PAGE", default: true),
        source_repository: ENV["SOURCE_REPOSITORY"] || ENV["GITHUB_REPOSITORY"],
        wiki_clone_url: ENV["WIKI_CLONE_URL"],
        wiki_branch: ENV["WIKI_BRANCH"] || "master",
        force: ENV["WIKI_FORCE"] == "1" || ENV["WIKI_FORCE"] == "true",
        branch: ENV["GITHUB_REF_NAME"],
        entry_page_name: ENV["ENTRY_PAGE_NAME"].then { |value| blank?(value) ? nil : value },
        github_host: ENV["GITHUB_SERVER_URL"] || "https://github.com",
        git_user_name: ENV["GIT_USER_NAME"] || "github-actions[bot]",
        git_user_email: ENV["GIT_USER_EMAIL"] || "github-actions[bot]@users.noreply.github.com"
      )
    end

    def self.truthy_env?(name, default:)
      value = ENV[name]
      return default if blank?(value)

      !%w[0 false no off].include?(value.downcase)
    end

    def self.blank?(value)
      value.nil? || value.to_s.strip.empty?
    end

    def migrate
      FileUtils.rm_rf(output_dir)
      FileUtils.mkdir_p(output_dir)

      validate_non_markdown_files!

      pages = migrator.pages
      pages.each do |filename, content|
        File.write(File.join(output_dir, filename), content)
      end

      non_markdown_files.each do |file|
        rel = relative_path(file)
        target = File.join(output_dir, rel)
        FileUtils.mkdir_p(File.dirname(target))
        FileUtils.cp(file, target)
      end

      pages
    end

    def publish
      raise ArgumentError, "wiki_repository required to publish" if blank?(@wiki_repository)
      raise ArgumentError, "wiki_deploy_token required to publish" if blank?(@wiki_deploy_token)

      pages = migrate
      configure_git(".")
      clone_or_update_wiki
      configure_git(wiki_checkout)
      copy_all_files_to_wiki
      add_home_index_entry if @update_home_page
      # Prove we can push the source-branch cleanup before we make the
      # irreversible wiki push, so a permissions/connectivity problem aborts
      # while both remotes are still untouched rather than after the wiki is
      # updated but the branch cleanup can't land.
      verify_source_push_access if Dir.exist?(docs_path)
      commit_and_push_wiki
      cleanup_source_branch

      PublishResult.new(wiki_url: entry_url, pages: pages)
    end

    private

    def blank?(value)
      self.class.blank?(value)
    end

    def normalize_wiki_repository(repository)
      normalized = repository.to_s.strip
      normalized = normalized.sub(%r{\Ahttps://github\.com/}, "")
      normalized = normalized.sub(%r{\.git\z}, "")
      normalized = normalized.sub(%r{/+\z}, "")
      normalized.end_with?(".wiki") ? normalized : "#{normalized}.wiki"
    end

    def source_repository_from_wiki
      @wiki_repository.sub(/\.wiki\z/, "")
    end

    def build_entry_url
      wiki_page_url(migrator.entry_wiki_name)
    end

    def wiki_page_url(wiki_name)
      "#{@github_host}/#{@source_repository}/wiki/#{wiki_name.tr(" ", "-")}"
    end

    # {source_file_path => its own flattened wiki URL} for every page in the
    # tree, used to repoint roadmap deep links at the specific sub-page rather
    # than collapsing everything onto the entry page.
    def page_urls
      return {} unless @source_repository

      migrator.wiki_names.each_with_object({}) do |(rel, wiki_name), memo|
        memo[File.join(docs_path, rel)] = wiki_page_url(wiki_name)
      end
    end

    def clone_url
      @wiki_clone_url || "https://x-access-token:#{@wiki_deploy_token}@github.com/#{@wiki_repository}.git"
    end

    def clone_or_update_wiki
      if Dir.exist?(File.join(wiki_checkout, ".git"))
        run("git", "-C", wiki_checkout, "-c", "credential.helper=", "fetch", "origin")
        run("git", "-C", wiki_checkout, "reset", "--hard", "origin/#{@wiki_branch}")
      else
        FileUtils.mkdir_p(File.dirname(wiki_checkout))
        run("git", "-c", "credential.helper=", "clone", clone_url, wiki_checkout)
        run("git", "-C", wiki_checkout, "checkout", "-B", @wiki_branch, "origin/#{@wiki_branch}")
      end
    end

    def configure_git(repository_path)
      return if blank?(@git_user_name) || blank?(@git_user_email)

      run("git", "-C", repository_path, "config", "user.name", @git_user_name)
      run("git", "-C", repository_path, "config", "user.email", @git_user_email)
      run("git", "-C", repository_path, "config", "commit.gpgsign", "false")
      run("git", "-C", repository_path, "config", "tag.gpgsign", "false")
    end

    def copy_all_files_to_wiki
      files = Dir.glob(File.join(output_dir, "**", "*")).reject { |p| File.directory?(p) }
      files.each do |file|
        rel = Pathname.new(file).relative_path_from(Pathname.new(output_dir)).to_s
        target = File.join(wiki_checkout, rel)

        if File.exist?(target) && !FileUtils.compare_file(file, target) && !@force
          raise Error, "Refusing to overwrite existing wiki page with different content: #{rel}. Set WIKI_FORCE=1 to overwrite."
        end

        FileUtils.mkdir_p(File.dirname(target))
        FileUtils.cp(file, target)
      end
      run("git", "-C", wiki_checkout, "add", ".")
    end

    def non_markdown_files
      Dir.glob(File.join(docs_path, "**", "*"))
        .reject { |p| File.directory?(p) || p.end_with?(".md") || File.basename(p).start_with?(".") }
    end

    def validate_non_markdown_files!
      return if @force

      unsupported = non_markdown_files.select do |file|
        ext = File.extname(file).downcase
        !SUPPORTED_EXTENSIONS.include?(ext)
      end

      return if unsupported.empty?

      message = "Unsupported non-markdown file type(s) found in docs tree: #{unsupported.map { |f| File.basename(f) }.join(", ")}."

      if interactive?
        @output.print "#{message}\nProceed anyway? (y/N): "
        response = @input.gets&.chomp
        unless /\Ay(?:es)?\z/i.match?(response)
          raise Error, "Aborted by user due to unsupported file types."
        end
      else
        raise Error, "#{message} Use WIKI_FORCE=1, the --force CLI option, or the force action input to override."
      end
    end

    def relative_path(path)
      Pathname.new(path).relative_path_from(Pathname.new(docs_path)).to_s
    end

    def interactive?
      return @interactive unless @interactive.nil?

      @input.tty? && !ENV["CI"]
    end

    def add_home_index_entry
      home_path = File.join(wiki_checkout, "Home.md")
      return unless File.exist?(home_path)

      entry_wiki_name = migrator.entry_wiki_name
      entry_page_path = File.join(output_dir, "#{entry_wiki_name}.md")
      entry_h1 = migrator.h1(File.read(entry_page_path)) || entry_wiki_name
      # Em dash matches the heading format used in every hand-authored Home.md
      # entry so the dedupe guard below actually recognizes existing entries.
      heading = "## Issue ##{migrator.issue_number} — #{entry_h1}"
      new_section = <<~SECTION
        #{heading}

        **Migrated to the wiki.** See [#{entry_h1}](#{entry_wiki_name.gsub(" ", "%20")}) for the full research.

      SECTION

      home = File.read(home_path)
      return if home.include?(heading)

      anchor = "## Settled Decisions"
      if home.include?(anchor)
        File.write(home_path, home.sub(anchor, new_section + anchor))
      else
        # No anchor heading — append the entry at the end of Home.md
        separator = if home.end_with?("\n\n")
          ""
        elsif home.end_with?("\n")
          "\n"
        else
          "\n\n"
        end
        File.write(home_path, home + separator + new_section)
      end
      run("git", "-C", wiki_checkout, "add", "Home.md")
    end

    def commit_and_push_wiki
      return unless staged_changes?(wiki_checkout)

      run("git", "-C", wiki_checkout, "commit", "-m", "Migrate #{docs_path} research to the wiki")
      run("git", "-C", wiki_checkout, "-c", "credential.helper=", "push", "origin", "HEAD:#{@wiki_branch}")
    end

    def verify_source_push_access
      run("git", "push", "--dry-run", "origin", "HEAD:refs/heads/#{source_branch}")
    end

    def cleanup_source_branch
      unless Dir.exist?(docs_path)
        puts "#{docs_path} already removed from this branch; skipping the cleanup commit."
        return
      end

      repoint_roadmap
      run("git", "rm", "-r", "--quiet", docs_path)
      run("git", "add", @roadmap_path) if File.exist?(@roadmap_path)
      return unless staged_changes?(".")

      run("git", "commit", "-m", "Migrate #{docs_path} research to the wiki; drop local tree")
      run("git", "push", "origin", "HEAD:refs/heads/#{source_branch}")
    end

    def repoint_roadmap
      return unless File.exist?(@roadmap_path)

      original = File.read(@roadmap_path)
      updated = WikiPromoter.repoint_references(
        original,
        docs_path: docs_path,
        entry_url: entry_url,
        repository: @source_repository,
        page_urls: page_urls,
        github_host: @github_host
      )
      File.write(@roadmap_path, updated) if updated != original
    end

    def source_branch
      branch = @branch || capture("git", "symbolic-ref", "-q", "--short", "HEAD").strip
      raise Error, "Could not determine a branch to push to" if blank?(branch)

      branch
    end

    def staged_changes?(repository_path)
      !system("git", "-C", repository_path, "diff", "--cached", "--quiet")
    end

    def run(*cmd)
      if @command_runner
        @command_runner.call(cmd)
      elsif !system(*cmd)
        raise Error, "Command failed: #{cmd.join(" ")}"
      end
    end

    def capture(*cmd)
      return @capture_runner.call(cmd) if @capture_runner

      stdout, status = Open3.capture2(*cmd)
      raise Error, "Command failed: #{cmd.join(" ")}" unless status.success?

      stdout
    end
  end
end
