# Google sign-in (task cyvasse-game-over-signin): the engine's
# POST /auth/google_oauth2 and OmniauthCallbacksController, beside the magic
# link, as the hub wires it. On only where the OAuth client is configured
# (GOOGLE_CLIENT_ID and GOOGLE_CLIENT_SECRET, with
# https://cyvasse.mcritchie.studio/auth/google_oauth2/callback registered on
# it); unset, the app stays magic link only and draws no Google button
# (config/initializers/studio.rb reads the same switch). Tests always run it,
# against OmniAuth's mock.
module CyvasseGoogleSignIn
  def self.enabled?(env: ENV, test: Rails.env.test?)
    test || (env["GOOGLE_CLIENT_ID"].present? && env["GOOGLE_CLIENT_SECRET"].present?)
  end
end

if CyvasseGoogleSignIn.enabled?
  Rails.application.config.middleware.use OmniAuth::Builder do
    provider :google_oauth2, ENV["GOOGLE_CLIENT_ID"], ENV["GOOGLE_CLIENT_SECRET"],
             scope: "email,profile", prompt: "select_account"
  end
end

# The request phase is a CSRF-checked POST (omniauth-rails_csrf_protection).
OmniAuth.config.allowed_request_methods = [ :post ]
