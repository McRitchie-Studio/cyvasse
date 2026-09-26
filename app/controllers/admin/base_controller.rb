# The app's own admin pages. Admins only (users.role "admin", the engine's
# admin role); a signed-in player who is not one gets a 404, so the pages do
# not announce themselves, and a signed-out visitor is sent to sign in.
module Admin
  class BaseController < ApplicationController
    before_action :require_admin_or_not_found

    private

    def require_admin_or_not_found
      raise ActiveRecord::RecordNotFound, "admins only" unless current_user&.admin?
    end
  end
end
