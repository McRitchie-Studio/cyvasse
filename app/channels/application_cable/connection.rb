module ApplicationCable
  # The websocket's player (task cyvasse-live-chat), read from the same signed
  # session cookie a page request is: the session's user, guests included
  # (a Play Now guest is a real user row). A socket with no signed-in player
  # is refused, since nothing Cyvasse streams is public. A device that logged out
  # is refused too: its cookie's sid is ended on the server
  # (Studio::UserSession.ended?, studio-engine docs/DEVICE_SESSIONS.md), so a copy
  # of a logged-out cookie cannot open a socket. respond_to? keeps the line a
  # no-op on an engine from before the helper.
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
      return unless id
      return if Studio::UserSession.respond_to?(:ended?) && Studio::UserSession.ended?(session)

      User.find_by(id:)
    end
  end
end
