require "test_helper"
require "open3"

# [integration] The booted app's two pools come from Cyvasse::ConnectionBudget
# (lib/cyvasse/connection_budget.rb): Active Record's connection pool
# (config/database.yml) and ActionCable's worker pool (config/application.rb),
# in this process and in a fresh boot under env overrides.
class ConnectionBudgetBootTest < ActiveSupport::TestCase
  Budget = Cyvasse::ConnectionBudget

  test "the live connection pool and ActionCable's worker pool read the budget" do
    expected = Budget.pool(ENV)
    assert_equal expected, ActiveRecord::Base.connection_pool.db_config.max_connections
    assert_equal Budget.cable_workers(ENV), Rails.application.config.action_cable.worker_pool_size
    assert_equal Budget.cable_workers(ENV), ActionCable.server.config.worker_pool_size
  end

  test "a booted app under overrides sizes both pools from them" do
    # The default worker pool (4) equals Rails' own default, so only a boot
    # under an override shows the setting is read, not left to Rails.
    script = "print [ActionCable.server.config.worker_pool_size, " \
             "ActiveRecord::Base.connection_pool.db_config.max_connections].join(',')"
    output, status = Open3.capture2(
      { "RAILS_ENV" => "test", "RAILS_MAX_THREADS" => "2", "CABLE_WORKER_POOL_SIZE" => "7" },
      Rails.root.join("bin/rails").to_s, "runner", script, chdir: Rails.root.to_s
    )
    assert status.success?, output
    assert_equal "7,10", output.lines.last.strip
  end
end
