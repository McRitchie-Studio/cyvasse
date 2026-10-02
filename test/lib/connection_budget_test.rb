require "test_helper"

# [unit] The database connection budget (lib/cyvasse/connection_budget.rb):
# the pool covers Puma's request threads plus ActionCable's workers, with one
# spare, at the defaults and under env overrides, and config/database.yml and
# config/puma.rb read it. test/integration/connection_budget_boot_test.rb boots
# the app and reads the live pools.
class ConnectionBudgetTest < ActiveSupport::TestCase
  Budget = Cyvasse::ConnectionBudget

  test "the defaults are 3 threads, 4 cable workers and a pool of 8" do
    assert_equal 3, Budget.threads({})
    assert_equal 4, Budget.cable_workers({})
    assert_equal 8, Budget.pool({})
  end

  test "the pool is at least threads plus cable workers, at the defaults and under overrides" do
    [
      {},
      { "RAILS_MAX_THREADS" => "5" },
      { "CABLE_WORKER_POOL_SIZE" => "2" },
      { "RAILS_MAX_THREADS" => "1", "CABLE_WORKER_POOL_SIZE" => "1" },
      { "RAILS_MAX_THREADS" => "6", "CABLE_WORKER_POOL_SIZE" => "8" }
    ].each do |env|
      demand = Budget.threads(env) + Budget.cable_workers(env)
      assert_operator Budget.pool(env), :>, demand, env.inspect
    end
  end

  test "env overrides change the threads, the workers and the pool together" do
    env = { "RAILS_MAX_THREADS" => "5", "CABLE_WORKER_POOL_SIZE" => "6" }
    assert_equal 5, Budget.threads(env)
    assert_equal 6, Budget.cable_workers(env)
    assert_equal 12, Budget.pool(env)
  end

  test "a blank, zero, negative or non-numeric value falls back to the default" do
    [ "", " ", "0", "-2", "three", "3.5" ].each do |value|
      env = { "RAILS_MAX_THREADS" => value, "CABLE_WORKER_POOL_SIZE" => value }
      assert_equal 3, Budget.threads(env), value.inspect
      assert_equal 4, Budget.cable_workers(env), value.inspect
      assert_equal 8, Budget.pool(env), value.inspect
    end
  end

  test "the defaults leave room under Heroku essential-0's 20 connections" do
    # Two web processes overlap during a restart; a release-phase migrate or a
    # one-off console takes a few more.
    assert_operator Budget.pool({}) * 2 + 2, :<=, 20
  end

  test "production's database.yml pool is the budget, and follows env overrides" do
    [ {}, { "RAILS_MAX_THREADS" => "5", "CABLE_WORKER_POOL_SIZE" => "6" } ].each do |overrides|
      with_env(overrides) do
        config = ActiveSupport::ConfigurationFile.parse(Rails.root.join("config/database.yml"))
        pool = config.fetch("production").fetch("max_connections")
        assert_equal Budget.pool(overrides), pool, overrides.inspect
        assert_operator pool, :>=, Budget.threads(overrides) + Budget.cable_workers(overrides)
      end
    end
  end

  test "Puma's thread count is the budget's, and the pool covers it" do
    require "puma/configuration"
    [ {}, { "RAILS_MAX_THREADS" => "5" } ].each do |overrides|
      with_env(overrides) do
        puma = Puma::Configuration.new({}, {}, ENV.to_h) { |user| user.load Rails.root.join("config/puma.rb").to_s }
        puma.clamp
        assert_equal Budget.threads(overrides), puma.options[:max_threads], overrides.inspect
        assert_equal Budget.threads(overrides), puma.options[:min_threads], overrides.inspect
        assert_operator Budget.pool(overrides), :>=, puma.options[:max_threads] + Budget.cable_workers(overrides)
      end
    end
  end

  private

  def with_env(overrides)
    names = %w[RAILS_MAX_THREADS CABLE_WORKER_POOL_SIZE]
    saved = names.to_h { |name| [ name, ENV[name] ] }
    names.each { |name| ENV.delete(name) }
    overrides.each { |name, value| ENV[name] = value }
    yield
  ensure
    saved.each { |name, value| value.nil? ? ENV.delete(name) : ENV[name] = value }
  end
end
