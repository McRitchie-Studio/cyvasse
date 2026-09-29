require "test_helper"

# [integration] Task cyvasse-blank-name-slug, over real requests: a magic-link
# sign-up creates an account with no name, and each one must still get its own
# slug (the second used to hit the slug index as "user-"); a Google sign-up
# keeps a name another player already holds, under a suffixed slug.
class BlankNameSignupTest < ActionDispatch::IntegrationTest
  teardown do
    OmniAuth.config.mock_auth[:google_oauth2] = nil
    OmniAuth.config.test_mode = false
  end

  def sign_up_by_magic_link(email)
    token = Studio::Link.create_magic_link(email:).token
    post link_consume_path(token:)
    User.find_by(email:)
  end

  test "a second nameless magic-link sign-up succeeds with its own slug" do
    first = sign_up_by_magic_link("first-new@example.com")
    get logout_path
    second = sign_up_by_magic_link("second-new@example.com")

    assert first, "the first sign-up creates an account"
    assert second, "the second nameless sign-up must create an account too"
    assert_nil second.name
    [ first, second ].each { |user| assert_match(/\Auser-[a-z0-9]+\z/, user.slug) }
    refute_equal first.slug, second.slug
    get root_path
    assert_response :redirect, "the new account is signed in and sent to its onboarding"
    assert_redirected_to onboarding_path
  end

  test "a Google sign-up keeps a name another player already holds" do
    User.create!(email: "arya-one@example.com", name: "Arya Stark")
    OmniAuth.config.test_mode = true
    OmniAuth.config.mock_auth[:google_oauth2] =
      OmniAuth::AuthHash.new(provider: "google_oauth2", uid: "g-arya-two", info: { email: "arya-two@example.com", name: "Arya Stark" })

    post "/auth/google_oauth2"
    follow_redirect!

    arya = User.find_by!(email: "arya-two@example.com")
    assert_equal [ "Arya Stark", "arya-stark-2" ], [ arya.name, arya.slug ]
  end
end
