require "test_helper"

# [component] /privacy and /terms (task cyvasse-footer-and-legal): public, the
# operating entity named, the contact email linked, and no page the policy
# covers contradicting it. The policy says the Site has no passwords, which is
# a claim about what the Site SHOWS as much as what it stores: the Industries
# legal pages shipped beside a /signup that asked for one.
class LegalPagesTest < ActionDispatch::IntegrationTest
  ENTITY = "McRitchie Studio LLC (doing business as McRitchie Studio)".freeze

  { privacy: [ "/privacy", "Privacy Policy" ], terms: [ "/terms", "Terms of Service" ] }.each do |key, (path, heading)|
    test "#{path} renders signed out and names the operator" do
      get path

      assert_response :success
      assert_select "title", text: "#{heading} · Cyvasse"
      assert_select "article[data-legal-page=?] h1", key.to_s, text: heading
      assert_select "[data-legal-entity]", text: ENTITY
      assert_select "article a[href=?]", "mailto:team@mcritchie.studio"
      assert_select "article p", text: /Last updated: October 3, 2026/
    end

    test "#{path} renders for a signed-in player too" do
      log_in_as(User.create!(email: "carl@example.com", name: "Carl Test", username: "carl"))
      get path

      assert_response :success
      assert_select "[data-legal-entity]", text: ENTITY
    end
  end

  test "the policy states the practices the code has" do
    get privacy_path
    text = css_select("article").text.squish

    [
      "The Site has no passwords",
      "We run no analytics or advertising trackers",
      "the Site's administrators can read them",
      "We did not carry over passwords",
      "Every one of these emails carries an unsubscribe link",
      "its current position on the board, the most recent move and when it was made",
      "We do not keep a history of earlier moves",
      "ZeroBounce checks that an email address can receive mail before we send it news email. It receives the email address only.",
      "Heroku", "Resend", "Google", "Anthropic"
    ].each { |phrase| assert_includes text, phrase }
    # The matches table keeps positions and the last move, never a move list
    # (Match#apply_turn): the policy must not claim one.
    assert_no_match(/every move, whose turn|time of each move/i, text)
    refute_includes Match.column_names, "moves"
    # No retention period, response time or age is promised.
    assert_no_match(/\b\d+\s+(days?|months?|years?)\b(?! after)/i, text.gsub("for 30 days", ""))
    assert_no_match(/under (the age of )?\d+/i, text)
  end

  test "the two pages link each other" do
    get privacy_path
    assert_select "article a[href=?]", terms_path
    get terms_path
    assert_select "article a[href=?]", privacy_path
  end

  # Every page a signed-out visitor reaches on the way to an account, and the
  # legal pages themselves. /signup redirects to /signin, followed here.
  PASSWORDLESS = %w[/ /signin /login /signup /leaderboard/join /play /privacy /terms].freeze

  PASSWORDLESS.each do |path|
    test "#{path} asks for no password" do
      get path
      follow_redirect! while response.redirect?

      assert_response :success, "#{path} must render signed out, or this test proves nothing"
      assert_select "input[type=password]", false, "#{path} renders a password field"
      assert_select "input[name*=password]", false, "#{path} posts a password"
    end
  end

  test "the onboarding a new account walks asks for no password" do
    log_in_as(User.create!(email: "newcomer@example.com"))
    get onboarding_path
    follow_redirect! while response.redirect?

    assert_response :success
    assert_select "input[type=password]", false
  end

  test "this app has no password to ask for" do
    refute Studio.auth_method?(:password)
    refute Studio.password_login_available?
    refute_includes User.column_names, "password_digest"
  end
end
