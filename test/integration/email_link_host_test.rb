require "test_helper"

# [integration] Mail links the established host while the site lives on the
# canonical one (task trustworthy-sign-in-email). With the move on
# (CANONICAL_HOST=cyvasse.xyz here, CANONICAL_REDIRECT=1 in production) and
# EMAIL_LINK_HOST=cyvasse.mcritchie.studio (production's default):
#
#   1. the sign-in email links https://cyvasse.mcritchie.studio/l/<token>
#   2. that GET 301s to https://cyvasse.xyz/l/<token>
#   3. the confirm page and its POST happen on cyvasse.xyz, and the session is
#      set there
#
# and an emailed ?ref= survives the same hop into the EmailReferral cookie.
# With the move off, mail and pages both stay on cyvasse.mcritchie.studio.
class EmailLinkHostTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper
  include MailHosts

  CANONICAL = "cyvasse.xyz".freeze
  EMAIL_HOST = "cyvasse.mcritchie.studio".freeze
  REF = "AbCdEfGhIjKlMnOpQrSt12".freeze

  setup do
    @veyjin = User.create!(email: "veyjin@example.com", name: "Veyjin Stark", username: "veyjin")
    ActionMailer::Base.deliveries.clear
  end

  def request_sign_in_email(host)
    perform_enqueued_jobs do
      post "https://#{host}/magic_link", params: { email: @veyjin.email, return_to: "/matches" }, as: :json
    end
    assert_response :success
    ActionMailer::Base.deliveries.last.tap { |mail| assert mail, "the sign-in email was sent" }
  end

  def link_in(mail) = mail.text_part.body.to_s[%r{https?://\S+/l/[\w-]+}]

  test "with the move on, the email links the old host and the click signs in on the canonical host" do
    with_hosts(canonical: CANONICAL, email: EMAIL_HOST) do
      mail = request_sign_in_email(CANONICAL)
      [ mail.html_part, mail.text_part ].each do |part|
        refute_includes part.body.to_s, CANONICAL
        assert_equal [ EMAIL_HOST ], hosts_in(part.body)
      end

      link = link_in(mail)
      token = link.split("/l/").last
      assert_equal "https://#{EMAIL_HOST}/l/#{token}", link

      get link
      assert_response :moved_permanently
      assert_equal "https://#{CANONICAL}/l/#{token}", response.location

      get response.location
      assert_response :success, "the confirm page renders on the canonical host"
      assert_equal CANONICAL, request.host
      assert_select "form[action=?]", "/l/#{token}"

      post "https://#{CANONICAL}/l/#{token}"
      assert_redirected_to %r{\Ahttps://#{Regexp.escape(CANONICAL)}/}
      assert_equal CANONICAL, request.host, "the consume POST is never redirected"

      get "https://#{CANONICAL}/matches"
      assert_response :success, "signed in on the canonical host"
      assert_equal CANONICAL, request.host
    end
  end

  test "with the move on, pages stay canonical on cyvasse.xyz" do
    with_hosts(canonical: CANONICAL, email: EMAIL_HOST) do
      get "https://#{CANONICAL}/rules"
      assert_select "link[rel=canonical][href=?]", "https://#{CANONICAL}/rules"
    end
  end

  test "an emailed ref survives the old-host hop into the EmailReferral cookie" do
    with_hosts(canonical: CANONICAL, email: EMAIL_HOST) do
      get "https://#{EMAIL_HOST}/play?ref=#{REF}"
      assert_response :moved_permanently
      assert_equal "https://#{CANONICAL}/play?ref=#{REF}", response.location

      get response.location
      assert_response :success
      assert_equal REF, cookies[EmailReferral::REF_COOKIE.to_s]
      assert_select "meta[name='email-goal-url'][content=?]", "#{EmailReferral.hub_url}/e/g/#{REF}?g="
    end
  end

  # Production with the flag unset puts both hosts on cyvasse.mcritchie.studio
  # (test/lib/canonical_host_test.rb); here CANONICAL_HOST stands in for that.
  test "with the move off, mail and pages are all on cyvasse.mcritchie.studio" do
    with_hosts(canonical: EMAIL_HOST, email: EMAIL_HOST) do
      mail = request_sign_in_email(EMAIL_HOST)
      [ mail.html_part, mail.text_part ].each { |part| assert_equal [ EMAIL_HOST ], hosts_in(part.body) }

      get link_in(mail)
      assert_response :success, "no redirect: the link opens where it points"

      get "https://#{EMAIL_HOST}/rules"
      assert_select "link[rel=canonical][href=?]", "https://#{EMAIL_HOST}/rules"
    end
  end
end
