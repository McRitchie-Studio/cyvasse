# An online match between two players (epic cyvasse-revival piece 6), stored
# in the legacy matches columns (see the CreateMatches migration for the
# encoding) so the legacy history can be imported as is.
#
#   pending      challenged; the challenger may already set up
#   new          accepted; each player sets up and submits their army
#   in progress  both armies placed; players alternate turns
#   finished     a king fell, a draw, a resignation, the clock ran out, or a
#                challenge left unanswered for the clock's length
#
# Every turn is checked on the server by CyvasseRules::Game, the Ruby mirror
# of the browser engine, before it is saved: a client can only ever submit a
# move the rules allow. The seven-day clock runs from time_of_last_move; the
# player who lets it run out forfeits (Match.expire_stale!).
class Match < ApplicationRecord
  PENDING = "pending"
  ACCEPTED = "new"
  IN_PROGRESS = "in progress"
  FINISHED = "finished"
  STATUSES = [ PENDING, ACCEPTED, IN_PROGRESS, FINISHED ].freeze
  PREGAME = [ PENDING, ACCEPTED ].freeze

  HOME = CyvasseRules::Game::HOME
  AWAY = CyvasseRules::Game::AWAY

  # Legacy commit 3d5e288: "Now you may take seven days to make a move."
  MOVE_CLOCK = 7.days

  # Why a match ended. Legacy rows leave finish_reason null.
  REASONS = %w[king draw resigned forfeit expired].freeze

  # A request the rules or the match's state refuse. The message is for the
  # player; controllers show it and log nothing.
  class Refused < StandardError; end

  belongs_to :home_user, class_name: "User", inverse_of: :home_matches
  belongs_to :away_user, class_name: "User", inverse_of: :away_matches
  belongs_to :winner, class_name: "User", optional: true

  validates :match_status, inclusion: { in: STATUSES }
  validates :finish_reason, inclusion: { in: REASONS }, allow_nil: true
  validate :two_different_players, on: :create

  scope :involving, ->(user) { where(home_user_id: user.id).or(where(away_user_id: user.id)) }
  scope :active, -> { where(match_status: [ *PREGAME, IN_PROGRESS ]) }
  scope :finished, -> { where(match_status: FINISHED) }
  scope :stale, ->(now = Time.current) { active.where(time_of_last_move: ...(now - MOVE_CLOCK)) }

  # ---- Starting and leaving a match ------------------------------------------

  def self.challenge!(challenger, username)
    opponent = User.find_by_username(username)
    raise Refused, "No player is called #{username.to_s.strip.presence || 'that'}." unless opponent
    raise Refused, "You cannot challenge yourself." if opponent.id == challenger.id
    if where(home_user: challenger, away_user: opponent, match_status: PENDING).exists?
      raise Refused, "You have already challenged #{opponent.username}."
    end

    match = create!(home_user: challenger, away_user: opponent, match_status: PENDING, match_against: "human",
                    turn: 0, time_of_last_move: Time.current, home_ready: false, away_ready: false, fast_game: false)
    match.notify(:challenged, opponent)
    match
  end

  def accept!(user)
    change_on_clock(user) do
      raise Refused, "Only #{away_user.username} can accept this challenge." unless seat(user) == :away
      raise Refused, "This challenge is no longer open." unless match_status == PENDING

      update!(match_status: ACCEPTED, time_of_last_move: Time.current)
    end
  end

  # Decline (the challenged player) or withdraw (the challenger), any time
  # before the first move. The legacy app deleted the match; so does this.
  def withdraw!(user)
    change(user) do
      raise Refused, "A match in play can only be resigned." unless PREGAME.include?(match_status)

      destroy!
    end
  end

  def resign!(user)
    change_on_clock(user) do
      raise Refused, "Only a match in play can be resigned." unless in_progress?

      finish!(winner: opponent_of(user), reason: "resigned")
    end
  end

  # ---- Setting up ------------------------------------------------------------

  # `lineup` is the player's army from their own seat ("unitIndex:hex|", hexes
  # 52-91), the format the browser and the legacy app share. Submitting it
  # locks it in; when both armies are in, the game starts.
  def set_up!(user, lineup)
    started = change_on_clock(user) do
      raise Refused, "Accept the challenge first." if match_status == PENDING && seat(user) == :away
      raise Refused, "This match is past its setup." unless PREGAME.include?(match_status)
      raise Refused, "Your army is already in place." if ready?(user)

      pairs = CyvasseRules::Game.parse_lineup!(lineup)
      if seat(user) == :away
        self.away_units_position = CyvasseRules::Game.format(CyvasseRules::Game.mirror_lineup(pairs))
        self.away_ready = true
      else
        self.home_units_position = CyvasseRules::Game.format(pairs)
        self.home_ready = true
      end
      self.time_of_last_move = Time.current
      start_game if match_status == ACCEPTED && home_ready && away_ready
      save!
      in_progress?
    end
    notify(:your_turn, user_to_move) if started
    self
  rescue CyvasseRules::Game::IllegalMove => e
    raise Refused, "That army cannot stand there: #{e.message}."
  end

  # ---- Playing ---------------------------------------------------------------

  # One whole turn from `user`'s seat: [[from, to]], or two steps for a
  # cavalry double jump. Refused unless it is their turn and every step is
  # legal; a move after the clock ran out forfeits instead (change_on_clock).
  def play!(user, steps)
    steps = normalize_steps(steps)
    steps = steps.map { |step| step.map { |hex| CyvasseRules::Board.mirror(hex) } } if seat(user) == :away

    change_on_clock(user) do
      raise Refused, "This match is not in play." unless in_progress?
      raise Refused, "It is #{user_to_move.username}'s turn." unless your_turn?(user)

      apply_turn(steps)
    end

    notify(:your_turn, user_to_move) if in_progress?
    self
  rescue CyvasseRules::Game::IllegalMove => e
    raise Refused, "That move is not allowed: #{e.message}."
  end

  # ---- The seven-day clock ---------------------------------------------------

  def deadline
    time_of_last_move && time_of_last_move + MOVE_CLOCK
  end

  def clock_expired?(now = Time.current)
    !finished? && deadline.present? && deadline < now
  end

  # Close every match whose clock has run out. Called before any page lists or
  # shows matches (so the rule holds without a scheduler) and by
  # `bin/rails matches:expire`, which a scheduler may run daily.
  def self.expire_stale!(scope = all, now: Time.current)
    scope.stale(now).find_each { |match| match.expire!(now) }
  end

  # Close this match if its clock has run out (re-checked under the lock, so
  # a move that landed first wins). Returns whether it expired.
  def expire!(now = Time.current)
    with_lock do
      next false unless clock_expired?(now)

      expire_on_clock
      true
    end
  end

  # ---- Who is who ------------------------------------------------------------

  def player?(user)
    user.present? && [ home_user_id, away_user_id ].include?(user.id)
  end

  def seat(user)
    return :home if user&.id == home_user_id
    return :away if user&.id == away_user_id

    nil
  end

  def team(user)
    { home: HOME, away: AWAY }[seat(user)]
  end

  def opponent_of(user)
    seat(user) == :home ? away_user : home_user
  end

  def user_to_move
    return nil unless in_progress?

    whos_turn == HOME ? home_user : away_user
  end

  def your_turn?(user)
    in_progress? && whos_turn == team(user)
  end

  def ready?(user)
    seat(user) == :home ? home_ready? : away_ready?
  end

  def pending? = match_status == PENDING
  def accepted? = match_status == ACCEPTED
  def in_progress? = match_status == IN_PROGRESS
  def finished? = match_status == FINISHED
  def pregame? = PREGAME.include?(match_status)

  # ---- What the board shows --------------------------------------------------

  # The match as `user`'s browser draws it: from their seat, so their army is
  # team 1 on the bottom rows whichever seat they hold (the away seat sees the
  # board turned round, hex 92 - n, as in the legacy app). The opponent's army
  # is withheld until the game starts: a setup is secret.
  def state_for(user)
    my_team = team(user)
    turned = seat(user) == :away
    view = ->(hex) { turned ? CyvasseRules::Board.mirror(hex) : hex }
    game = to_game
    show_all = in_progress? || finished?

    units = game.units.filter_map do |unit|
      mine = unit.team == my_team
      next unless mine || show_all

      [ mine ? 1 : 0, unit.index, unit.alive? ? view.(unit.hex) : nil, unit.status.to_s ]
    end

    {
      id: id,
      status: match_status,
      phase: if in_progress? then "play" elsif finished? then "over" else "setup" end,
      version: updated_at.to_f.to_s,
      you: { username: user.username, ready: ready?(user) },
      opponent: { username: opponent_of(user).username, ready: ready?(opponent_of(user)) },
      seat: seat(user),
      can_accept: pending? && seat(user) == :away,
      can_set_up: pregame? && !ready?(user) && !(pending? && seat(user) == :away),
      your_turn: your_turn?(user),
      turn: turn.to_i,
      offense: in_progress? ? (whos_turn == my_team ? 1 : 0) : nil,
      units: units,
      last_move: hexes(last_move).map(&view),
      util_move: hexes(utility_saved_hex).map(&view).first,
      deadline: deadline&.iso8601,
      winner: winner_id.nil? ? nil : (winner_id == user.id ? 1 : 0),
      finish_reason: finish_reason
    }
  end

  def to_game
    CyvasseRules::Game.new(home: home_units_position, away: away_units_position,
                           offense: in_progress? ? whos_turn : nil, turn: turn)
  end

  # Mail the player whose move it is (or who was challenged). Delivered through
  # the engine's outbox after the write commits; a player without an email
  # address is skipped.
  def notify(action, user)
    return if user&.email.blank?

    Studio::Email.deliver(MatchMailer, action, self, user, to: user.email, user: user)
  end

  private

  # Every state change: participants only, under a row lock, in one
  # transaction. Returns the block's value.
  def change(user)
    raise Refused, "You are not playing in this match." unless player?(user)

    with_lock { yield }
  end

  # A change that the seven-day clock may already have decided: a stale page
  # can post a move, a resignation, an acceptance or an army after the
  # deadline. The forfeit (or, before play, the expiry) is settled first under
  # the lock and the request is refused, so a late click never overturns the
  # result the clock gave. The refusal is raised after the lock is released so
  # the settled result commits.
  def change_on_clock(user)
    expired = false
    value = change(user) do
      if clock_expired?
        expire_on_clock
        expired = true
        next
      end
      yield
    end
    raise Refused, "The seven-day clock ran out; the match is over." if expired

    value
  end

  def start_game
    game = to_game
    result = game.start!
    self.who_started = game.first_mover
    self.whos_turn = game.offense
    self.turn = game.turn
    self.match_status = IN_PROGRESS
    finish!(winner: nil, reason: "draw", save: false) if result.over
  end

  def apply_turn(steps)
    game = to_game
    result = game.play!(steps)
    self.home_units_position = game.position(HOME)
    self.away_units_position = game.position(AWAY)
    self.turn = game.turn
    self.whos_turn = game.offense
    self.last_move = result.last_move.join(",")
    self.utility_saved_hex = result.util_move&.to_s
    self.time_of_last_move = Time.current
    if result.over
      winner = { HOME => home_user, AWAY => away_user }[result.winner]
      finish!(winner: winner, reason: winner ? "king" : "draw", save: false)
    end
    save!
  end

  # The clock ran out. In play, the player to move forfeits; before play, the
  # match simply closes with no result, as the legacy sweep did.
  def expire_on_clock
    if in_progress?
      finish!(winner: whos_turn == HOME ? away_user : home_user, reason: "forfeit")
    else
      finish!(winner: nil, reason: "expired")
    end
  end

  def finish!(winner:, reason:, save: true)
    self.match_status = FINISHED
    self.winner = winner
    self.finish_reason = reason
    save! if save
    return unless winner

    loser = winner.id == home_user_id ? away_user : home_user
    User.update_counters(winner.id, wins: 1)
    User.update_counters(loser.id, losses: 1)
  end

  def normalize_steps(steps)
    list = Array(steps).map { |step| Array(step).map { |hex| hex_number(hex) } }
    raise Refused, "A turn is one or two steps of [from, to]." unless list.size.between?(1, 2) && list.all? { |s| s.size == 2 && s.all?(Integer) }

    list
  end

  # A hex as JSON or a form sends it: 12 or "12"; anything else is nil.
  def hex_number(value)
    return value if value.is_a?(Integer)

    value.to_i if value.is_a?(String) && value.match?(/\A\d{1,2}\z/)
  end

  # "12,34" -> [12, 34]; the legacy "95" (no mark) and blanks -> [].
  def hexes(string)
    string.to_s.split(",").filter_map { |n| Integer(n, exception: false) }.select { |n| n.between?(1, CyvasseRules::Board::HEX_COUNT) }
  end

  def two_different_players
    errors.add(:away_user, "must be someone else") if home_user_id.present? && home_user_id == away_user_id
  end
end
