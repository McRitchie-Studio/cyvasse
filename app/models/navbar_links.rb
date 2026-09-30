# The navbar's own links (task cyvasse-nav-links): My games, Chat with the
# player's unread messages as a badge (task cyvasse-live-chat; ChatBroadcasts
# keeps it live), and Leaderboard with the player's live rank as a badge. Handed to the engine navbar through
# Studio.navbar_links (config/initializers/studio.rb), which resolves them once
# per render pass, so the rank is one query a page.
#
# Takes the view and reads only current_user from it, with literal paths: the
# engine's own pages (sign-in, error logs) render the navbar from a view that
# has neither the app's helpers nor its route helpers.
module NavbarLinks
  MATCHES = "/matches".freeze
  LEADERBOARD = "/leaderboard".freeze
  CHAT = "/conversations".freeze
  # The badge shows up to this many unread messages; more reads "9+".
  UNREAD_CAP = 9

  module_function

  def call(view)
    player = view.current_user if view.respond_to?(:current_user)
    links = []
    # /matches sends a player without a username to choose one, and a
    # signed-out visitor to sign in: the link shows only where it opens games.
    if player&.username.present?
      links << { label: "My games", href: MATCHES, active: %r{\A#{MATCHES}(/|\z)} }
    end
    # Every signed-in player has a Chat hub, a guest included: it lists who
    # they have played, or says to go and play someone.
    if player
      links << { label: "Chat", href: CHAT, active: %r{\A#{CHAT}(/|\z)}, badge: unread_badge(player) }
    end
    links << { label: "Leaderboard", href: LEADERBOARD, active: %r{\A#{LEADERBOARD}(/|\z)},
               badge: rank_badge(player) }
  end

  # "#12" for a player on the live board; nil (no badge) for anyone else.
  # The engine resolves the links inside the layout with no rescue, so a
  # failed rank query would 500 every page, the error pages included: it
  # degrades to no badge and lands in ErrorLog instead.
  def rank_badge(player)
    row = Leaderboard.rank_for(player)
    "##{row.rank}" if row
  rescue StandardError => e
    log_failure(e)
    nil
  end

  # "3" for three unread messages from people, "9+" past the cap, nil (no
  # badge) at none. Degrades to no badge on a failed count, as the rank does.
  def unread_badge(player)
    label(player.unread_messages_count)
  rescue StandardError => e
    log_failure(e)
    nil
  end

  def label(count)
    return nil unless count.positive?

    count > UNREAD_CAP ? "#{UNREAD_CAP}+" : count.to_s
  end

  def log_failure(error)
    ErrorLog.capture!(error)
  rescue StandardError => e
    Rails.logger.error("[NavbarLinks] rank badge failed (#{error.class}: #{error.message}); " \
                       "ErrorLog.capture! failed too (#{e.class}: #{e.message})")
  end
end
