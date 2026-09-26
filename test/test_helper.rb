ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
Dir[File.expand_path("support/**/*.rb", __dir__)].each { |file| require file }

module ActiveSupport
  class TestCase
    # Single-process on purpose — the house convention for local suites.
    parallelize(workers: 1)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Studio::EmailSetting memoises the row it read in process state, which the
    # transaction rollback cannot undo; clear it so one test's override never
    # leaks into the next.
    teardown do
      Studio::EmailSetting.forget! if defined?(Studio::EmailSetting)
    end
  end
end

class ActionDispatch::IntegrationTest
  # Sign in through the REAL engine flow: mint a Studio::Link magic link and
  # POST the consume endpoint, which burns the token and starts the session.
  def log_in_as(user)
    raise ArgumentError, "log_in_as requires a user with an email" if user.email.blank?

    token = Studio::Link.create_magic_link(email: user.email).token
    post link_consume_path(token: token)
  end
end
