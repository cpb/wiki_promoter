# frozen_string_literal: true

require "test_helper"
require "yaml"

# Guards the composite action against the class of bug where its Ruby include
# path or executable path (built from ${{ github.action_path }}) points at a
# file that does not actually ship in the repo. github.action_path resolves to
# the directory that contains action.yml (action/), so lib/ and exe/ -- which
# live at the repo root -- must be reached one level up.
class ActionTest < Minitest::Test
  ACTION_DIR = File.expand_path("../action", __dir__)
  ACTION_YML = File.join(ACTION_DIR, "action.yml")

  def publish_run_script
    action = YAML.safe_load_file(ACTION_YML)
    step = action.fetch("runs").fetch("steps").find { |s| s["id"] == "publish" }
    refute_nil step, "action.yml has no step with id: publish"

    # Resolve the two indirections the run script uses: the GitHub-provided
    # action path, and the gem_root shell variable derived from it.
    step.fetch("run")
      .gsub("${{ github.action_path }}", ACTION_DIR)
      .gsub("${gem_root}", "#{ACTION_DIR}/..")
  end

  def test_include_paths_resolve_to_a_loadable_gem
    includes = publish_run_script.scan(/-I"([^"]+)"/).flatten
    refute_empty includes, "publish step has no -I include path"

    includes.each do |include_dir|
      entry = File.join(include_dir, "wiki_promoter.rb")
      assert File.exist?(entry),
        "action.yml -I#{include_dir} does not contain wiki_promoter.rb (resolved: #{File.expand_path(entry)})"
    end
  end

  def test_executable_path_resolves_to_the_shipped_binary
    exe_path = publish_run_script[/"([^"]*exe\/wiki-promoter)"/, 1]
    refute_nil exe_path, "publish step does not invoke exe/wiki-promoter"
    assert File.exist?(exe_path),
      "action.yml executable #{exe_path} does not exist (resolved: #{File.expand_path(exe_path)})"
  end
end
