# A live match (task live-match-engine): an online match played in one
# sitting, on short clocks, where nobody is ever left waiting on an absent
# player.
#
#   setup   SETUP_CLOCK from the start for both armies. A computer seat sets
#           up at once. A player still not ready when it runs out gets a
#           random army (the board shows it filling in) and a strike.
#   play    MOVE_CLOCK per turn. A computer seat thinks for BOT_THINK seconds,
#           then plays. A player who lets the clock run out has a computer
#           move made for them and takes a strike.
#   strikes STRIKES_TO_REPLACE missed clocks and a computer player takes that
#           seat, until its player takes it back (#take_back_seat!). The
#           strikes stay counted, so one more missed clock hands it over again.
#
# There is no background worker: #tick! settles whatever is due whenever
# either player's board asks for the state (MatchesController), under the row
# lock, so two polls landing together settle it once.
module LiveMatch
  extend ActiveSupport::Concern

  SETUP_CLOCK = 60.seconds
  MOVE_CLOCK_LIVE = 30.seconds
  WARNING = 10.seconds
  BOT_THINK = (3..14)
  STRIKES_TO_REPLACE = 2
  # A match that ended this recently still opens the game-over modal when its
  # page is loaded (a guest back from signing in); an older one does not.
  GAME_OVER_FRESH = 5.minutes

  # The old site's computer players (User#computer?), by their username, with
  # the names the /play screen gives them (app/javascript/cyvasse/setups.js).
  COMPUTER_NAMES = {
    "qavo" => "Qavo Nogarys", "tyrion" => "Tyrion Lannister", "haldon" => "Haldon Halfmaester",
    "doran" => "Doran Martell", "ben" => "Ben Plumm", "aegon" => "Aegon Targaryen"
  }.freeze
  COMPUTER_LEGACY_IDS = { "qavo" => 2, "tyrion" => 3, "haldon" => 4, "doran" => 5, "ben" => 6, "aegon" => 7 }.freeze

  class_methods do
    # Start a live match with both armies still to place. `computer: true`
    # seats a computer player in the away seat, which sets up at once.
    def start_live!(home_user, away_user = nil, computer: false, rng: Random.new)
      away_user = computer_player(rng:) if computer
      now = Time.current
      match = create!(home_user:, away_user:, match_status: Match::ACCEPTED, match_against: computer ? "computer" : "human",
                      live: true, turn: 0, time_of_last_move: now, clock_started_at: now,
                      home_ready: false, away_ready: false, fast_game: true, away_bot: computer)
      match.tick!(rng:)
    end

    # One of the six named computer players, created if this database lacks it
    # (a new database has no legacy import).
    def computer_player(rng: Random.new)
      username = COMPUTER_NAMES.keys.sample(random: rng)
      User.find_by(legacy_id: COMPUTER_LEGACY_IDS.fetch(username)) ||
        User.create!(legacy_id: COMPUTER_LEGACY_IDS.fetch(username), username:, name: COMPUTER_NAMES.fetch(username))
    end
  end

  # Settle whatever the clocks say is due. Safe to call on every poll.
  def tick!(rng: Random.new)
    return self unless live? && !finished?

    with_lock do
      settle_setup(rng) if accepted?
      settle_play(rng) if in_progress?
    end
    self
  end

  def bot_seat?(seat)
    seat == :home ? home_bot? : away_bot?
  end

  def strikes(seat)
    seat == :home ? home_strikes : away_strikes
  end

  # A computer took this seat over after missed clocks (not a computer
  # opponent from the start).
  def taken_over?(seat)
    bot_seat?(seat) && strikes(seat) >= STRIKES_TO_REPLACE
  end

  # A player took this seat back from the computer (#take_back_seat!): the
  # strikes that handed it over, and no computer in it.
  def took_back?(seat)
    !bot_seat?(seat) && strikes(seat) >= STRIKES_TO_REPLACE
  end

  # `user` takes back the seat a computer took over, and plays on. Never
  # across a computer move: when it is the seat's turn, the computer's move
  # lands first, under the same lock, and the seat is handed back after it.
  def take_back_seat!(user, rng: Random.new)
    change(user) do
      raise Match::Refused, "This match is not in play." unless live? && in_progress?

      seat = seat(user)
      raise Match::Refused, "Your seat is already yours." unless taken_over?(seat)

      bot_turn!(rng) if seat_to_move == seat
      next unless in_progress?

      self["#{seat}_bot"] = false
      save!
    end
    self
  end

  def auto_set_up?(seat)
    seat == :home ? home_auto_set_up? : away_auto_set_up?
  end

  # When the clock now running ends: the setup clock, or the move clock of a
  # player to move (a computer's turn has no clock; it is "thinking").
  def live_clock_ends_at
    return unless live? && clock_started_at
    return clock_started_at + SETUP_CLOCK if accepted?
    return clock_started_at + MOVE_CLOCK_LIVE if in_progress? && !bot_seat?(seat_to_move)

    nil
  end

  def seat_to_move
    return unless in_progress?

    whos_turn == Match::HOME ? :home : :away
  end

  # What the live board needs, from `user`'s seat.
  def live_state_for(user)
    mine = seat(user)
    theirs = mine == :home ? :away : :home
    ends_at = live_clock_ends_at
    {
      server_time: Time.current.iso8601(3),
      clock: ends_at && {
        kind: accepted? ? "setup" : "move",
        ends_at: ends_at.iso8601(3),
        seconds: (accepted? ? SETUP_CLOCK : MOVE_CLOCK_LIVE).to_i,
        warning: WARNING.to_i
      },
      thinking: in_progress? && bot_seat?(seat_to_move) && seat_to_move == theirs,
      strikes: { you: strikes(mine), opponent: strikes(theirs) },
      computer: opponent_of(user).computer?,
      taken_over: { you: taken_over?(mine), opponent: taken_over?(theirs) },
      took_back: { you: took_back?(mine), opponent: took_back?(theirs) },
      auto_set_up: { you: auto_set_up?(mine), opponent: auto_set_up?(theirs) },
      # The game-over modal's line to a guest (modals/_game_over): signing in
      # puts this win on the leaderboard.
      board_win: leaderboard_win?(user),
      just_ended: finished? && finished_at.present? && finished_at > GAME_OVER_FRESH.ago
    }
  end

  # The name a player sees for `user`: a computer player's full name.
  def display_name_of(user)
    (user.computer? && COMPUTER_NAMES[user.username]) || user.username
  end

  private

  def settle_setup(rng)
    %i[home away].each { |seat| place_army(seat, CyvasseRules::Bot.lineup(rng:)) if bot_seat?(seat) && !seat_ready?(seat) }
    if Time.current >= clock_started_at + SETUP_CLOCK
      %i[home away].each do |seat|
        next if seat_ready?(seat)

        place_army(seat, CyvasseRules::Bot.random_lineup(rng:))
        self["#{seat}_auto_set_up"] = true
        strike!(seat)
      end
    end
    start_game if home_ready? && away_ready?
    save!
  end

  def settle_play(rng)
    # A human timeout makes the next turn a computer's or another human's, so
    # each pass settles at most one overdue turn; two is plenty per poll.
    2.times do
      break unless in_progress?

      seat = seat_to_move
      if bot_seat?(seat)
        if bot_due_at.nil?
          schedule_bot(rng)
          save!
          break
        end
        break if Time.current < bot_due_at

        bot_turn!(rng)
      elsif Time.current >= clock_started_at + MOVE_CLOCK_LIVE
        strike!(seat)
        bot_turn!(rng)
      else
        break
      end
    end
  end

  def seat_ready?(seat)
    seat == :home ? home_ready? : away_ready?
  end

  # A lineup from the seat's own rows (52-91), as Match#set_up! stores it.
  def place_army(seat, lineup)
    pairs = CyvasseRules::Game.parse_lineup!(lineup)
    if seat == :away
      self.away_units_position = CyvasseRules::Game.format(CyvasseRules::Game.mirror_lineup(pairs))
      self.away_ready = true
    else
      self.home_units_position = CyvasseRules::Game.format(pairs)
      self.home_ready = true
    end
  end

  def strike!(seat)
    self["#{seat}_strikes"] = strikes(seat) + 1
    self["#{seat}_bot"] = true if strikes(seat) >= STRIKES_TO_REPLACE
  end

  def bot_turn!(rng)
    steps = CyvasseRules::Bot.choose_turn(to_game, rng:)
    if steps
      apply_turn(steps)
    else
      save!
    end
  end

  # A new turn (or the first): its clock starts now, and a computer to move
  # gets its thinking time.
  def live_turn_started(rng = Random.new)
    return unless live?

    self.clock_started_at = Time.current
    self.bot_due_at = nil
    schedule_bot(rng) if in_progress? && bot_seat?(seat_to_move)
  end

  def schedule_bot(rng)
    self.bot_due_at = Time.current + rng.rand(BOT_THINK).seconds
  end
end
