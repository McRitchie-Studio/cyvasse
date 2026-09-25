class ApplicationController < ActionController::Base
  # Passwordless auth, hub SSO awareness, and rescue_and_log / ErrorLog.
  # NOTE: this adds `before_action :require_authentication` to every
  # controller. PagesController and GamesController opt out
  # (test/integration/auth_gate_test.rb pins both sides).
  include Studio::ErrorHandling

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes
end
