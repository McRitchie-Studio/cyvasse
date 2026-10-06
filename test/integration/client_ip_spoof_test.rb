require "test_helper"

# [unit] [integration] WHOSE ADDRESS A REQUEST IS COUNTED AGAINST
# (config/initializers/forwarded_headers.rb).
#
# Rails reads `request.remote_ip`, and Rack reads `request.ip`. Both believe a
# `Forwarded` header the caller wrote unless Cyvasse drops it from Rack's
# priority list, because Rack 3 prefers it to X-Forwarded-For and the Heroku
# router does not touch it.
#
# The requests here have the shape production's do: the app is reached from the
# router's private address, and the router has appended the real client to the
# right of X-Forwarded-For. Setting REMOTE_ADDR to a public address cannot see
# any of this.
class ClientIpSpoofTest < ActionDispatch::IntegrationTest
  ROUTER = "10.1.2.3".freeze
  CLIENT = "198.51.100.7".freeze
  CLAIMED = "203.0.113.200".freeze

  SPOOFS = {
    "a Forwarded header" => { "HTTP_FORWARDED" => "for=#{CLAIMED}" },
    "a Forwarded header with a proxy chain" => { "HTTP_FORWARDED" => "for=#{CLAIMED};proto=https, for=10.9.9.9" },
    "a quoted IPv6 Forwarded header" => { "HTTP_FORWARDED" => "for=\"[2001:db8::1]\"" },
    "a leftmost X-Forwarded-For entry" => { "HTTP_X_FORWARDED_FOR" => "#{CLAIMED}, #{CLIENT}" },
    "both at once" => { "HTTP_FORWARDED" => "for=#{CLAIMED}", "HTTP_X_FORWARDED_FOR" => "#{CLAIMED}, #{CLIENT}" }
  }.freeze

  setup { EmailHandoffsController::RATE_STORE.clear }

  def heroku_env(path, method: "GET", **headers)
    env = Rack::MockRequest.env_for(path, method: method, "REMOTE_ADDR" => ROUTER, "HTTP_X_FORWARDED_FOR" => CLIENT)
    env.merge(headers)
  end

  def remote_ip(env)
    seen = nil
    app = lambda do |inner|
      seen = ActionDispatch::Request.new(inner).remote_ip
      [200, {}, []]
    end
    ActionDispatch::RemoteIp.new(app).call(env)
    seen
  end

  def hand_off(xff:, forwarded: nil)
    headers = { "REMOTE_ADDR" => ROUTER, "X-Forwarded-For" => xff }
    headers["Forwarded"] = forwarded if forwarded
    get email_handoff_path, params: { assertion: "x" }, headers: headers
    response.status
  end

  test "[unit] only X-Forwarded-For is read for the client address" do
    assert_equal [:x_forwarded], Rack::Request.forwarded_priority
  end

  test "[unit] with no spoof, the address is the one the router appended" do
    env = heroku_env("/auth/email_handoff")

    assert_equal CLIENT, Rack::Request.new(env).ip
    assert_equal CLIENT, remote_ip(env)
  end

  SPOOFS.each do |name, headers|
    test "[unit] #{name} does not change the address Rack or Rails sees" do
      env = heroku_env("/auth/email_handoff", **headers)

      assert_equal CLIENT, Rack::Request.new(env).ip
      assert_equal CLIENT, remote_ip(env)
    end
  end

  test "[unit] a Forwarded header cannot set the host or the scheme either" do
    env = heroku_env("/auth/email_handoff", "HTTP_FORWARDED" => "for=#{CLAIMED};host=evil.example;proto=http",
                                            "HTTP_HOST" => "cyvasse.example", "HTTP_X_FORWARDED_PROTO" => "https")

    assert_equal "cyvasse.example", ActionDispatch::Request.new(env).host
    assert_equal "https", ActionDispatch::Request.new(env).scheme
    assert_equal "cyvasse.example", Rack::Request.new(env).host
  end

  # --- through the real middleware ------------------------------------------------------

  test "[integration] rotating a spoofed address on every request does not escape the email handoff limit" do
    statuses = Array.new(EmailHandoffsController::RATE + 1) do |i|
      hand_off(xff: "192.0.2.#{i + 1}, #{CLIENT}", forwarded: "for=203.0.113.#{i + 1}")
    end

    assert_equal [302] * EmailHandoffsController::RATE + [429], statuses
  end

  # The limit is per address, so a second real client behind the same router
  # keeps a bucket of its own: the property above is about the key, not a
  # global cap.
  test "[integration] a different real client is still counted on its own" do
    EmailHandoffsController::RATE.times { hand_off(xff: CLIENT) }
    assert_equal 429, hand_off(xff: CLIENT)

    assert_equal 302, hand_off(xff: "198.51.100.8")
  end
end
