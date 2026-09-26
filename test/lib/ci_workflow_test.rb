require "test_helper"
require "yaml"

# [unit] The CI workflow is the verdict review and the release sweep read, so
# its shape is pinned: it runs on every rung of the ladder and runs the suite.
class CiWorkflowTest < ActiveSupport::TestCase
  def workflow
    @workflow ||= YAML.load_file(Rails.root.join(".github/workflows/ci.yml"))
  end

  # YAML 1.1 reads the bare key `on` as true.
  def triggers
    workflow["on"] || workflow[true]
  end

  test "CI runs on pull requests and on every rung of the ladder" do
    assert triggers.key?("pull_request")
    assert_equal %w[accepted main release], triggers.dig("push", "branches").sort
  end

  test "a job runs the test suite against Postgres" do
    steps = workflow["jobs"].values.flat_map { |job| job["steps"] || [] }
    runs = steps.filter_map { |step| step["run"] }

    assert runs.any? { |run| run.include?("bin/rails db:test:prepare test") }, "no step runs the unit suite"
  end

  test "every job has a timeout" do
    workflow["jobs"].each do |name, job|
      assert job["timeout-minutes"], "job #{name} has no timeout-minutes; GitHub's default is six hours"
    end
  end

  test "the system tests run in CI, and there are system tests to run" do
    runs = workflow["jobs"].values.flat_map { |job| job["steps"] || [] }.filter_map { |step| step["run"] }

    assert runs.any? { |run| run.include?("test:system") }, "no step runs test/system"
    refute_empty Dir[Rails.root.join("test/system/**/*_test.rb")], "a system lane over an empty directory tests nothing"
  end

  test "the JavaScript unit tests run in CI, and there are tests to run" do
    runs = workflow["jobs"].values.flat_map { |job| job["steps"] || [] }.filter_map { |step| step["run"] }

    assert runs.any? { |run| run.include?("bin/test-js") }, "no step runs the game engine's unit tests"
    refute_empty Dir[Rails.root.join("test/javascript/*_test.js")], "bin/test-js would have nothing to run"
  end
end
