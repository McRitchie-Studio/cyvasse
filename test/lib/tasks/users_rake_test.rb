require "test_helper"
require "rake"

# [unit] users:seed_identities is the release post-deploy command, so it must
# exist, seed exactly the identities, and be safe to run twice.
class UsersRakeTest < ActiveSupport::TestCase
  setup do
    Rails.application.load_tasks unless Rake::Task.task_defined?("users:seed_identities")
    @task = Rake::Task["users:seed_identities"]
    @task.reenable
  end

  test "seeds every identity and is idempotent" do
    assert_output(/Seeded admin: alex@mcritchie.studio/) { @task.invoke }
    @task.reenable

    assert_no_difference -> { User.count } do
      assert_output(/Seeded viewer: mack@mcritchie.studio/) { @task.invoke }
    end
    assert_equal User::SEED_IDENTITIES.map { |i| i[:email] }.sort,
                 User.where(email: User::SEED_IDENTITIES.map { |i| i[:email] }).pluck(:email).sort
  end
end
