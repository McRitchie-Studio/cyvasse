require "test_helper"

# [integration] Task cyvasse-google-race-guard, over a real callback request:
# Google says the address is NOT verified, and the address holder's row lands
# between our lookup and our create!. The callback must sign nobody in.
class GoogleRaceGuardTest < ActionDispatch::IntegrationTest
  # minitest 6 ships no stub (minitest/mock is gone). This file swaps
  # User.create! and GoogleOauthValidator.new, both inherited.
  # The original is captured before the swap and put back in the ensure, so it
  # returns even when the block raises: a method the class defines itself is
  # redefined from the saved original, an inherited one by removing the
  # override.
  def swap_class_method(klass, name, replacement)
    own = klass.singleton_class.method_defined?(name, false)
    original = klass.singleton_class.instance_method(name) if own
    klass.define_singleton_method(name, &replacement)
    begin
      yield
    ensure
      if own
        klass.singleton_class.send(:define_method, name, original)
      else
        klass.singleton_class.send(:remove_method, name)
      end
    end
  end

  teardown do
    OmniAuth.config.mock_auth[:google_oauth2] = nil
    OmniAuth.config.test_mode = false
  end

  test "an unverified Google callback that loses the race signs nobody in" do
    OmniAuth.config.test_mode = true
    OmniAuth.config.mock_auth[:google_oauth2] =
      OmniAuth::AuthHash.new(provider: "google_oauth2", uid: "g-racer", info: { email: "holder@example.com", name: "Racer" })
    unverified = GoogleOauthValidator::Result.new(ok: true, email: "holder@example.com", email_verified: false, reason: nil)
    validator = Object.new.tap { |v| v.define_singleton_method(:validate!) { unverified } }
    holder = nil
    insert_then_collide = lambda do |**|
      holder = User.new(email: "holder@example.com", name: "Holder").tap(&:save!)
      raise ActiveRecord::RecordNotUnique, "duplicate key value"
    end

    swap_class_method(GoogleOauthValidator, :new, ->(**) { validator }) do
      swap_class_method(User, :create!, insert_then_collide) do
        post "/auth/google_oauth2"
        follow_redirect!
      end
    end

    assert holder, "the race inserted the holder"
    assert_redirected_to login_path
    assert_nil session[Studio.session_key]
    assert_nil holder.reload.uid
  end
end
