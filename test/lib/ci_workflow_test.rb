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

  test "no system-test lane that would test nothing" do
    refute workflow["jobs"].key?("system-test"),
           "test/system has no tests yet; a lane over an empty directory is a green that means nothing"
  end
end
