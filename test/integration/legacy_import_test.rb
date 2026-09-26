require "test_helper"
require "rake"

# [integration] The legacy import end to end: the rake task on the synthetic
# CSVs, a rerun that changes nothing, and an imported player signing in to
# find their old games on My games and the match board.
class LegacyImportIntegrationTest < ActionDispatch::IntegrationTest
  DIR = Rails.root.join("test/fixtures/files/legacy")

  setup do
    Rails.application.load_tasks unless Rake::Task.task_defined?("legacy:import")
    @task = Rake::Task["legacy:import"]
    @task.reenable
  end

  test "the rake task imports, prints counts only, and a rerun changes nothing" do
    output = run_task
    assert_match(/Users read: 10\n  imported: 10\n/, output)
    assert_match(/Matches read: 10\n  imported: 9\n/, output)
    refute_match(/@/, output, "the task must never print an email")

    before = snapshot
    rerun = run_task
    assert_match(/  imported: 0\n  already present \(legacy id\): 10\n/, rerun)
    assert_match(/  imported: 0\n  already present \(legacy id\): 9\n/, rerun)
    assert_equal before, snapshot, "a second run must change no row"
  end

  test "the task refuses without a folder" do
    with_env("LEGACY_CSV_DIR" => nil) do
      assert_raises(SystemExit) { capture_io { @task.invoke } }
    end
  end

  test "an imported player signs in and finds their legacy games" do
    run_task
    rook = User.find_by!(legacy_id: 11)
    log_in_as(rook)

    get matches_path
    assert_response :success
    assert_includes response.body, "left unfinished"
    assert_includes response.body, "won (king captured)"

    get match_path(Match.find_by!(legacy_id: 107))
    assert_response :success
    get match_path(Match.find_by!(legacy_id: 108), format: :json)
    assert_response :success
    assert_equal "abandoned", response.parsed_body["finish_reason"]
  end

  private

  def run_task
    @task.reenable
    with_env("LEGACY_CSV_DIR" => DIR.to_s) { capture_io { @task.invoke }.first }
  end

  def snapshot
    [ User.order(:id).map(&:attributes), Match.order(:id).map(&:attributes) ]
  end

  def with_env(vars)
    saved = vars.keys.to_h { |k| [ k, ENV[k] ] }
    vars.each { |k, v| ENV[k] = v }
    yield
  ensure
    saved.each { |k, v| ENV[k] = v }
  end
end
