require "test_helper"

# Production runs ActionCable on the redis pubsub adapter (config/cable.yml).
# That adapter file calls `gem "redis", ">= 4", "< 6"`; with redis 6.0.0 in the
# bundle, loading it raised Gem::LoadError ("can't activate redis (>= 4, < 6),
# already activated redis-6.0.0"), so production chat broadcasts never
# delivered. The test env uses the test adapter, so nothing else loads this
# file here: this test is the guard on the Gemfile's `redis ~> 5.4` pin.
class RedisCableAdapterTest < ActiveSupport::TestCase
  test "the bundled redis satisfies the ActionCable redis adapter" do
    assert_nothing_raised { require "action_cable/subscription_adapter/redis" }
    assert_equal "ActionCable::SubscriptionAdapter::Redis",
      ActionCable::SubscriptionAdapter::Redis.name
  end

  test "the bundled redis is below 6" do
    version = Gem.loaded_specs.fetch("redis").version
    assert_operator version, :>=, Gem::Version.new("4")
    assert_operator version, :<, Gem::Version.new("6"),
      "ActionCable's redis adapter requires redis < 6; bundled #{version}"
  end

  test "production's cable config names the redis adapter" do
    config = ActiveSupport::ConfigurationFile.parse(Rails.root.join("config/cable.yml"))
    assert_equal "redis", config.fetch("production").fetch("adapter")
  end
end
