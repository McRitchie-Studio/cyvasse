require "test_helper"

# [integration] Cyvasse::CanonicalHostRedirect through the whole middleware
# stack. The "Cyvasse is back" emails link to cyvasse.mcritchie.studio with a
# ?ref= delivery token; that host, www, the herokuapp host and any other 301 to
# cyvasse.xyz on the same path and query, while /up, the bot API, the
# cable and every non-GET stay where they are.
class CanonicalHostRedirectTest < ActionDispatch::IntegrationTest
  CANONICAL = "cyvasse.xyz".freeze
  OLD_HOST = "cyvasse.mcritchie.studio".freeze
  REF = "AbCdEfGhIjKlMnOpQrSt12".freeze

  setup do
    @previous = ENV["CANONICAL_HOST"]
    ENV["CANONICAL_HOST"] = CANONICAL
  end

  teardown { ENV["CANONICAL_HOST"] = @previous }

  test "the old host 301s to the canonical host keeping path, query and ref" do
    host! OLD_HOST
    get "/play?ref=#{REF}&utm_source=email&x=a%20b"

    assert_response :moved_permanently
    assert_equal "https://#{CANONICAL}/play?ref=#{REF}&utm_source=email&x=a%20b", response.location
  end

  test "the old host's home page with a ref lands on the canonical home page" do
    host! OLD_HOST
    get "/?ref=#{REF}"

    assert_redirected_to "https://#{CANONICAL}/?ref=#{REF}"
    assert_equal 301, response.status
  end

  test "http on the old host goes straight to https on the canonical host in one hop" do
    get "http://#{OLD_HOST}/rules"

    assert_equal 301, response.status
    assert_equal "https://#{CANONICAL}/rules", response.location
  end

  test "www, the herokuapp host and any other host redirect too" do
    %w[www.cyvasse.xyz cyvasse-614ed5f7e99d.herokuapp.com other.example.com].each do |host|
      host! host
      get "/leaderboard"

      assert_equal 301, response.status, "#{host} must redirect"
      assert_equal "https://#{CANONICAL}/leaderboard", response.location
    end
  end

  test "HEAD redirects like GET" do
    host! OLD_HOST
    head "/about"

    assert_equal 301, response.status
    assert_equal "https://#{CANONICAL}/about", response.location
  end

  test "the canonical host is served, not redirected" do
    host! CANONICAL
    get "/rules"

    assert_response :success
  end

  test "the canonical host matches whatever its case" do
    host! "Cyvasse.XYZ"
    get "/rules"

    assert_response :success
  end

  test "/up is never redirected, on any host" do
    [ OLD_HOST, "www.cyvasse.xyz", "cyvasse-614ed5f7e99d.herokuapp.com" ].each do |host|
      host! host
      get "/up"

      assert_response :success, "#{host}/up must answer the probe itself"
    end
  end

  test "a POST on the old host is served where it lands, never redirected" do
    host! OLD_HOST
    post "/magic_link", params: { email: "arya@example.com" }

    refute_equal 301, response.status
    refute_match(/#{Regexp.escape(CANONICAL)}/, response.location.to_s)
  end

  test "PATCH and DELETE are not redirected either" do
    host! OLD_HOST
    patch "/skin", params: { skin: "vector" }
    refute_equal 301, response.status

    delete "/logout"
    refute_equal 301, response.status
  end

  test "the bot API and the cable are exempt even for a GET" do
    host! OLD_HOST
    get "/api/bot/inbox"
    refute_equal 301, response.status, "a bot's bearer token must not be bounced across hosts"

    get "/cable"
    refute_equal 301, response.status
  end

  test "a live page's JSON poll on the old host is served there, never bounced cross-site" do
    host! OLD_HOST
    get "/rules", headers: { "Sec-Fetch-Mode" => "cors", "Accept" => "application/json" }
    refute_equal 301, response.status, "a fetch poll must not follow a 301 to another site (CORS)"

    get "/rules", headers: { "Accept" => "application/json" }
    refute_equal 301, response.status, "no Sec-Fetch-Mode, JSON-only Accept stays put"

    get "/rules", headers: { "X-Requested-With" => "XMLHttpRequest" }
    refute_equal 301, response.status, "an XHR stays put"
  end

  test "a browser navigation on the old host is redirected" do
    host! OLD_HOST
    get "/rules", headers: { "Sec-Fetch-Mode" => "navigate", "Accept" => "text/html,application/xhtml+xml" }

    assert_equal 301, response.status
    assert_equal "private, max-age=3600", response.headers["cache-control"]
  end

  test "a spoofed X-Forwarded-Host cannot pass the old host off as canonical" do
    host! OLD_HOST
    get "/rules", headers: { "X-Forwarded-Host" => CANONICAL }

    assert_equal 301, response.status
  end

  test "the ref survives the hop and is credited on the canonical host" do
    host! OLD_HOST
    get "/play?ref=#{REF}"
    follow_redirect!

    assert_response :success
    assert_equal CANONICAL, request.host
    assert_select "meta[name='email-goal-url'][content=?]", "#{EmailReferral.hub_url}/e/g/#{REF}?g="
  end

  test "a player redirected from the old host can sign in fresh on the canonical host" do
    user = User.create!(email: "arya@example.com", name: "Arya", username: "arya")
    host! OLD_HOST
    get "/matches"
    assert_redirected_to "https://#{CANONICAL}/matches"

    host! CANONICAL
    https!
    log_in_as(user)
    get "/matches"

    assert_response :success
  end

  test "with no canonical host nothing redirects" do
    ENV.delete("CANONICAL_HOST")
    host! OLD_HOST
    get "/rules"

    assert_response :success
  end
end
