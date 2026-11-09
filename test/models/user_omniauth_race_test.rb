require "test_helper"

# [unit] Task cyvasse-google-race-guard. from_omniauth's RecordNotUnique rescue
# runs when a concurrent callback wrote a row first. It may link by address only
# when Google verified that address, the same rule as the main path; otherwise a
# race hands an unverified address its holder's account.
class UserOmniauthRaceTest < ActiveSupport::TestCase
  # minitest 6 ships no stub (minitest/mock is gone). This file swaps
  # User.create! (inherited) and Studio::Account.race_winner (its own).
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

  def google_auth(email:, uid:)
    OmniAuth::AuthHash.new(provider: "google_oauth2", uid: uid, info: { email: email, name: "Racer" })
  end

  # The race: the address holder appears between the lookups and our create!.
  def racing(holder_email)
    holder = nil
    insert_then_collide = lambda do |**|
      holder = User.new(email: holder_email, name: "Holder")
      holder.save!
      raise ActiveRecord::RecordNotUnique, "duplicate key value"
    end
    swap_class_method(User, :create!, insert_then_collide) { yield -> { holder } }
  end

  test "an unverified address never wins the race for its holder's account" do
    racing("holder@example.com") do |holder|
      result = User.from_omniauth(google_auth(email: "holder@example.com", uid: "g-racer"), email_verified: false)

      assert holder.call, "the race inserted the holder"
      refute_equal holder.call, result
      assert_nil result
      assert_nil holder.call.reload.uid
    end
  end

  test "a verified address finds its holder after the race" do
    racing("holder@example.com") do |holder|
      result = User.from_omniauth(google_auth(email: "holder@example.com", uid: "g-racer"), email_verified: true)

      assert_equal holder.call, result
    end
  end

  test "a race won by the same Google identity returns that row" do
    winner = nil
    insert_then_collide = lambda do |**|
      winner = User.new(email: "racer@example.com", name: "First Tab", provider: "google_oauth2", uid: "g-racer").tap(&:save!)
      raise ActiveRecord::RecordNotUnique, "duplicate key value"
    end

    swap_class_method(User, :create!, insert_then_collide) do
      result = User.from_omniauth(google_auth(email: "racer@example.com", uid: "g-racer"), email_verified: false)

      assert winner, "the race inserted the winner"
      assert_equal winner, result
    end
  end

  test "a race that matches nobody is logged and signs nobody in" do
    racing("someone-else@example.com") do
      assert_difference -> { ErrorLog.count }, 1 do
        assert_nil User.from_omniauth(google_auth(email: "racer@example.com", uid: "g-racer"), email_verified: true)
      end
    end
  end

  test "the race rescue asks the engine's race_winner, passing the collision" do
    calls = []
    real = Studio::Account.method(:race_winner)
    spy = lambda do |model, **kw|
      calls << [ model, kw ]
      real.call(model, **kw)
    end

    racing("holder@example.com") do |holder|
      swap_class_method(Studio::Account, :race_winner, spy) do
        result = User.from_omniauth(google_auth(email: "holder@example.com", uid: "g-racer"), email_verified: true)

        assert_equal holder.call, result
      end
    end

    assert_equal 1, calls.size
    model, kw = calls.first
    assert_equal User, model
    assert_equal({ provider: "google_oauth2", uid: "g-racer", email: "holder@example.com", email_verified: true },
                 kw.except(:error))
    assert_kind_of ActiveRecord::RecordNotUnique, kw[:error]
  end

  test "swap_class_method puts back the original when the block raises" do
    where = Studio::Account.method(:race_winner).source_location
    assert_raises(RuntimeError) do
      swap_class_method(Studio::Account, :race_winner, ->(*, **) { :stub }) { raise "boom" }
    end
    assert_equal where, Studio::Account.method(:race_winner).source_location
    assert_nil Studio::Account.race_winner(User, provider: "google_oauth2", uid: "nobody")

    assert_raises(RuntimeError) do
      swap_class_method(User, :create!, ->(**) { :stub }) { raise "boom" }
    end
    refute User.singleton_class.method_defined?(:create!, false), "the inherited create! is back"
  end
end
