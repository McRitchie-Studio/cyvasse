require "test_helper"

# [unit] Every migration the RESOLVED studio-engine ships is installed here, by
# bare name. A version floor cannot see a migration nobody copied, and a missing
# outbox table fails silently: Studio::Email.deliver falls back to a plain
# deliver_later and the local inbox stays empty (new-app-onboarding-sop.md
# section 7). Remedy: bin/rails studio_engine:install:migrations && db:migrate.
class EngineMigrationsInstalledTest < ActiveSupport::TestCase
  def self.bare_name(path)
    File.basename(path.to_s).sub(/\A\d+_/, "").sub(/\.[a-z_]+\.rb\z/, "").sub(/\.rb\z/, "")
  end

  test "every engine migration is installed in db/migrate" do
    gem_dir = Studio::Engine.root.join("db/migrate")
    shipped = Dir[gem_dir.join("*.rb")].map { |path| self.class.bare_name(path) }
    installed = Dir[Rails.root.join("db/migrate/*.rb")].map { |path| self.class.bare_name(path) }

    assert_operator shipped.size, :>=, 1, "found no engine migrations at #{gem_dir}; the guard would pass vacuously"
    assert_empty shipped - installed,
                 "studio-engine #{Studio::VERSION} ships migrations this app never installed"
  end

  test "the email outbox table exists" do
    assert Studio::EmailDelivery.available?
  end
end
