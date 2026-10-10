require "test_helper"
require "yaml"

# [unit] The CI workflow is the verdict review and the release sweep read, so
# its shape is pinned: it runs on every rung of the ladder and calls the hub's
# reusable suite with the inputs that make it this app's suite.
class CiWorkflowTest < ActiveSupport::TestCase
  SUITE = "McRitchie-Studio/mcritchie-studio/.github/workflows/reusable-ci.yml@main".freeze

  # Every input the call passes. A lane left at the hub's default (`javascript`,
  # `system`) is absent; each one here switches off a hub lane this app has no
  # use for, or names this app's own command.
  INPUTS = {
    "island-animator" => false,
    "playwright" => false,
    "rails-shards" => false,
    "await-gem-propagation" => false,
    "postgres-image" => "public.ecr.aws/docker/library/postgres:18",
    "gem-audit-command" => "bin/bundler-audit",
    "importmap-audit-command" => "bin/importmap audit",
    "system-packages" => "libpq-dev libvips postgresql-client",
    "system-setup-command" => "bin/rails tailwindcss:build",
    "system-command" => "bin/rails db:test:prepare test test:system"
  }.freeze

  def workflow
    @workflow ||= YAML.load_file(Rails.root.join(".github/workflows/ci.yml"))
  end

  # YAML 1.1 reads the bare key `on` as true.
  def triggers
    workflow["on"] || workflow[true]
  end

  def call
    workflow.dig("jobs", "ci")
  end

  test "CI runs on pull requests and on every rung of the ladder" do
    assert triggers.key?("pull_request")
    assert_equal %w[accepted main release], triggers.dig("push", "branches").sort
    assert_empty triggers["push"].keys & %w[paths paths-ignore], "a path filter leaves a rung with no verdict"
  end

  test "no concurrency block can cancel a rung's run" do
    refute workflow.key?("concurrency"), "a cancelled run reads as RED to the release tooling"
  end

  test "the one job calls the hub's reusable suite and nothing else" do
    assert_equal [ "ci" ], workflow["jobs"].keys
    assert_equal SUITE, call["uses"]
    assert_equal %w[uses with], call.keys.sort,
                 "an `if:` skips every lane and still reads green; the suite takes no secrets"
  end

  test "the call passes exactly this app's inputs" do
    assert_equal INPUTS, call["with"]
  end

  test "the call runs the whole Rails suite, system tests included, and there are system tests" do
    command = call.dig("with", "system-command")

    assert_includes command.split, "test", "no lane runs the unit and integration suite"
    assert_includes command.split, "test:system", "no lane runs test/system"
    assert_equal "db:test:prepare", command.split[1], "a leading rake task routes both tiers through rake"
    refute_empty Dir[Rails.root.join("test/system/**/*_test.rb")], "a system lane over an empty directory tests nothing"
  end

  test "the JavaScript lane stays on, and there are tests for it to run" do
    refute call["with"].key?("javascript"), "the hub's javascript lane (bin/test-js) is on by default"
    assert File.executable?(Rails.root.join("bin/test-js")), "the lane runs bin/test-js"
    refute_empty Dir[Rails.root.join("test/javascript/*_test.js")], "bin/test-js would have nothing to run"
  end

  test "the scripts the lanes run from this tree exist" do
    %w[.github/scripts/apt-retry bin/brakeman bin/bundler-audit bin/importmap bin/rubocop].each do |path|
      assert File.executable?(Rails.root.join(path)), "#{path} is missing or not executable"
    end
  end

  test "a failed system test's screenshot keeps the page HTML" do
    require "application_system_test_case"

    assert_equal "1", ENV["RAILS_SYSTEM_TESTING_SCREENSHOT_HTML"]
  end
end
