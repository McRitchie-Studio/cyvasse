require "test_helper"
require "yaml"
require "open3"

# The release copies studio-engine migrations in verbatim when it bumps the
# engine (studio_engine:install:migrations). They keep the engine's style, so
# ci / static must not lint them: 0.137.0's create_studio_connections failed
# Layout/SpaceInsideArrayLiteralBrackets on release fcb8904. Same rule as
# voicebox and alex-build.
class RubocopEngineMigrationsTest < ActiveSupport::TestCase
  CONFIG = Rails.root.join(".rubocop.yml")

  # [unit] The config excludes copied engine migrations and keeps RuboCop's
  # default excludes (merge, not replace).
  test "[unit] .rubocop.yml excludes engine-copied migrations and merges excludes" do
    config = YAML.safe_load(CONFIG.read)
    assert_includes config.dig("AllCops", "Exclude"), "db/migrate/*.studio_engine.rb"
    assert_includes config.dig("AllCops", "Exclude"), "db/schema.rb"
    assert_includes Array(config.dig("inherit_mode", "merge")), "Exclude"
  end

  # [integration] RuboCop itself skips an engine migration styled the engine's
  # way, even when it is named explicitly (--force-exclusion, as CI's whole-repo
  # run would skip it).
  test "[integration] rubocop skips an engine-styled migration copied into db/migrate" do
    path = Rails.root.join("db/migrate/20991231000000_rubocop_probe.studio_engine.rb")
    path.write(<<~RUBY)
      class RubocopProbe < ActiveRecord::Migration[8.1]
        def change
          add_index :users, [:id, :created_at]
        end
      end
    RUBY
    out, status = Open3.capture2e("bin/rubocop", "--force-exclusion", "--format", "simple", path.to_s, chdir: Rails.root.to_s)
    assert status.success?, out
    assert_no_match(/SpaceInsideArrayLiteralBrackets/, out)
  ensure
    path&.delete if path&.exist?
  end
end
