# WHICH PROXY HEADER NAMES THE CLIENT. One answer for every reader of the
# client address: Rails' `request.remote_ip`, and Rack's `request.ip` for any
# middleware that builds a plain Rack::Request.
#
# Rack 3 reads the standard `Forwarded` header BEFORE `X-Forwarded-For`
# (Rack::Request.forwarded_priority defaults to [:forwarded, :x_forwarded]),
# and Rails' RemoteIp middleware takes its list from the same method
# (ActionDispatch::Request#forwarded_for is Rack's). The Heroku router neither
# sets nor strips `Forwarded`, so without this line a caller writes their own
# address:
#
#     Forwarded: for=203.0.113.9
#
# and every reader of remote_ip believes it: the per-address rate limit on
# GET /auth/email_handoff (EmailHandoffsController, whose `rate_limit` keys on
# request.remote_ip by default) counts them as that address, a fresh one on
# each request if they like, and the "Started GET ... for <ip>" line Rails
# logs for every request names it. The chat, username and bot API limits key
# on the player or the bot token, not the address, and are not affected.
#
# The header the platform controls is X-Forwarded-For. The Heroku router
# appends the address it received the request from to the right of any list
# the client sent (https://devcenter.heroku.com/articles/http-routing). Rack
# and Rails both walk the list from the right and stop at the first address
# that is not a private one, so a value the client put on the left is never
# reached. With `Forwarded` out of the list, every reader gets the address the
# router wrote.
#
# It also keeps `Forwarded: proto=...` and `Forwarded: host=...` away from
# Rack::Request#scheme, #host and #authority, which read through the same
# priority list. Rails' own request.host reads X-Forwarded-Host or Host and
# never `Forwarded`; Cyvasse::CanonicalHostRedirect reads Host itself.
# X-Forwarded-Proto and X-Forwarded-Port, which the router sets, are
# unaffected.
#
# A request with no `Forwarded` header, which is every browser request the
# router forwards, is read exactly as it would be without this line.
#
# If a proxy that speaks `Forwarded` is ever put in front of the router,
# revisit this. test/integration/client_ip_spoof_test.rb holds the property.
Rack::Request.forwarded_priority = [ :x_forwarded ]
