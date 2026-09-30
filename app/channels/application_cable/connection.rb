module ApplicationCable
  # The websocket's player (task cyvasse-live-chat), read from the same signed
  # session cookie a page request is: the session's user, guests included
  # (a Play Now guest is a real user row). A socket with no signed-in player
  # is refused, since nothing Cyvasse streams is public.
  class Connection < ActionCable::Connection::Base
    identified_by :current_user

    def connect
      self.current_user = session_user || reject_unauthorized_connection
    end

    private

    # Studio::ErrorHandling#current_user, from the cookie: the session store
    # is the encrypted cookie named by the session options.
    def session_user
      session = cookies.encrypted[Rails.application.config.session_options[:key]]
      id = session.is_a?(Hash) ? session[Studio.session_key.to_s] : nil
      User.find_by(id:) if id
    end
  end
end
