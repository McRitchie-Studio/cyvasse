# A player pressing Play Now (task play-now-matchmaking): they search for
# another live player for SEARCH_TIME; two searchers are paired into a live
# match (the earlier one takes the home seat), and a searcher still alone
# when the time is up plays a computer player (Match.start_live!).
#
# A search counts only while its page keeps asking (last_seen_at, refreshed
# by every poll): a player who closed the tab is never paired, so nobody waits
# out an empty seat's clocks.
#
# Pairing runs under one Postgres advisory lock, so two players pressing
# Play Now together are paired once, never twice.
class LiveSeek < ApplicationRecord
  SEARCH_TIME = 20.seconds
  # The "You vs them" splash between a match being made and its board
  # opening (live_seek_controller.js). The setup clock starts after it.
  SPLASH = 5.seconds
  ALIVE = 4.seconds
  LOCK_KEY = 20_260_929

  belongs_to :user
  belongs_to :match, optional: true

  scope :open, -> { where(match_id: nil) }

  # How long a search lasts; the browser tests shorten it.
  def self.search_time = Rails.configuration.x.live_search_time.presence || SEARCH_TIME

  # How long the versus splash runs; the browser tests shorten it.
  def self.splash_time = Rails.configuration.x.live_splash_time.presence || SPLASH

  # Start searching for `user`, pairing at once with a live searcher if one is
  # waiting. Any earlier open search of theirs is dropped.
  def self.join!(user, now: Time.current)
    locked do
      open.where(user:).delete_all
      partner = open.where.not(user:).where(created_at: (now - search_time)..)
                    .where(last_seen_at: (now - ALIVE)..).order(:created_at).first
      seek = create!(user:, last_seen_at: now)
      if partner
        match = Match.start_live!(partner.user, user, setup_grace: splash_time)
        partner.update!(match:)
        seek.update!(match:)
      end
      seek
    end
  end

  def self.locked(&)
    transaction do
      connection.execute("SELECT pg_advisory_xact_lock(#{LOCK_KEY})")
      yield
    end
  end

  def ends_at = created_at + self.class.search_time

  # Called by every poll: mark the searcher present, and when the time is up
  # with nobody found, start the match against a computer player. `computer`
  # is "Play the computer now": that same match, without waiting.
  def settle!(now: Time.current, computer: false)
    self.class.locked do
      reload
      update_columns(last_seen_at: now)
      if match.nil? && (computer || now >= ends_at)
        update!(match: Match.start_live!(user, computer: true, setup_grace: self.class.splash_time))
      end
    end
    self
  end
end
