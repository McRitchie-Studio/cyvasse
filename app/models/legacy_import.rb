# Imports the players, matches, messages and saved lineups of the old Cyvasse
# (the personal Heroku app cyvasse-game, 2014-2023) from the CSV export of its
# database: epic cyvasse-revival pieces 10a (players, matches) and 10b
# (messages, lineups). `bin/rails legacy:import` runs it.
#
#   LegacyImport.new(users_csv: path, matches_csv: path,
#                    messages_csv: path, setups_csv: path).run  # => LegacyImport::Report
#
# messages_csv and setups_csv are optional; left out, that part is not run.
#
# The CSVs hold emails, password hashes and private messages: never commit
# them or print a row.
# The importer reads only the columns below; the password digest (and every
# other profile column) is never read, so it cannot land here. The Report
# carries counts only.
#
# Idempotent. Every row keeps its old id in `legacy_id`, and a rerun inserts
# only the legacy ids not yet present; it never updates a row it finds, so a
# second run changes nothing. It runs in one transaction: a failure leaves
# nothing half-imported.
#
# A failure prints no row. Postgres quotes the failing row in its error and
# ActiveRecord adds the whole INSERT with every value, so any error inside the
# run is replaced by LegacyImport::Failed, which names only the table, the
# batch and its legacy id range (or the step), and the error's class, and
# carries no cause (Ruby and rake print a cause under the error).
#
# Players (users.csv)
#   username, wins, losses and the joined date (created_at) come over as they
#   were; the email is trimmed and downcased, as the engine's sign-in looks it
#   up. Nobody is made an admin, and no email is sent.
#   Usernames: legacy uniqueness was exact-case, and 223 names carry stray
#   spaces, so 88 rows collide once trimmed and compared in any case. The RULE:
#   the earliest account (lowest legacy id) keeps the name; every later one,
#   and any legacy name already taken by a player of the new app, becomes
#   "<name>_<legacy id>".
#   Emails: the earliest account keeps a shared address; a later one, or one an
#   account of the new app already holds, imports with no email (the unique
#   index allows only one) and so cannot sign in until an admin sets one.
#   The computer opponents (legacy ids 2-10, seeded with the app; the away
#   seat of every computer match) import with no email, so nothing is ever
#   mailed to them. Legacy id 1 is the old admin account and imports as an
#   ordinary player.
#
# Matches (matches.csv)
#   Every column of the legacy table comes over verbatim (the new table kept
#   the legacy names and encoding). The legacy app never stored a winner, so
#   it is derived, as the legacy code decided it:
#     finished, a king (unit 17) in the graveyard  -> the other side won ("king")
#     finished human match, a player on the move    -> the clock ran out on
#       that player, who forfeited (legacy User#active_matches) ("forfeit")
#     finished human match, never started           -> "expired", no winner
#     finished computer match with no captured king -> "abandoned", no winner
#   Every unfinished match (pending, new, in progress) closes at import as
#   finished, "abandoned", no winner, so the seven-day clock
#   (Match.expire_stale!) never forfeits a years-old game and rewrites a
#   player's record. Win/loss counters are never touched: users.wins/losses
#   are the legacy records, which already counted every legacy result.
#   A match whose player is missing from users.csv is skipped.
#
# Messages (messages.csv)
#   Every column comes over one to one (see the CreateMessages migration):
#   the text as it was, blank ones included (the legacy chat stored them);
#   sender and receiver mapped to the imported players through their legacy
#   ids; read as it was. A message addressed to nobody (legacy receiver 0,
#   posted with match 0) or to a player missing from users.csv is skipped: a
#   conversation needs both people. A message whose match was not imported
#   (deleted on the legacy site, or skipped above) keeps its conversation with
#   no match, as a message of a deleted match does in the new app.
#
# Lineups (setups.csv)
#   Every column comes over one to one (see the CreateSetups migration), each
#   lineup to its owner through their legacy id; one whose owner is missing is
#   skipped. The army string is kept verbatim; Setup#lineup reads it, turns
#   round the few saved from the away seat, and offers nothing for one that is
#   not a whole army. Both are counted.
require "csv"

class LegacyImport
  COMPUTER_LEGACY_IDS = User::COMPUTER_LEGACY_IDS
  KING_INDEX = 17
  BATCH = 1_000
  ROLLED_BACK = "Nothing was imported: the whole run rolled back. " \
                "The database's message is withheld because it quotes row values."

  # The only error the run raises. Its message is safe to print.
  class Failed < StandardError; end

  # Counts only; never a row.
  Report = Struct.new(:users_read, :users_imported, :users_already_present, :usernames_renamed,
                      :emails_dropped_duplicate, :emails_dropped_computer, :matches_read, :matches_imported,
                      :matches_already_present, :matches_by_outcome, :matches_skipped,
                      :messages_read, :messages_imported, :messages_already_present, :messages_blank,
                      :messages_without_match, :messages_skipped,
                      :setups_read, :setups_imported, :setups_already_present, :setups_turned_round,
                      :setups_not_an_army, :setups_skipped, keyword_init: true) do
    def self.empty
      new(users_read: 0, users_imported: 0, users_already_present: 0, usernames_renamed: 0,
          emails_dropped_duplicate: 0, emails_dropped_computer: 0, matches_read: 0, matches_imported: 0,
          matches_already_present: 0, matches_by_outcome: Hash.new(0), matches_skipped: Hash.new(0),
          messages_imported: 0, messages_already_present: 0, messages_blank: 0, messages_without_match: 0,
          messages_skipped: Hash.new(0), setups_imported: 0, setups_already_present: 0, setups_turned_round: 0,
          setups_not_an_army: 0, setups_skipped: Hash.new(0))
    end

    def lines
      [
        "Users read: #{users_read}",
        "  imported: #{users_imported}",
        "  already present (legacy id): #{users_already_present}",
        "  usernames renamed <name>_<legacy id> (collision in any case, earliest keeps it): #{usernames_renamed}",
        "  imported without email, address already held: #{emails_dropped_duplicate}",
        "  imported without email, computer opponent: #{emails_dropped_computer}",
        "Matches read: #{matches_read}",
        "  imported: #{matches_imported}",
        "  already present (legacy id): #{matches_already_present}",
        *matches_by_outcome.sort.map { |outcome, n| "  imported as #{outcome}: #{n}" },
        *matches_skipped.sort.map { |reason, n| "  skipped, #{reason}: #{n}" },
        *message_lines,
        *setup_lines
      ]
    end

    # messages_read and setups_read stay nil when that part was not run.
    def message_lines
      return [ "Messages: not run (no messages.csv)" ] if messages_read.nil?

      [
        "Messages read: #{messages_read}",
        "  imported: #{messages_imported}",
        "  already present (legacy id): #{messages_already_present}",
        "  imported with blank text: #{messages_blank}",
        "  imported without a match (match not imported): #{messages_without_match}",
        *messages_skipped.sort.map { |reason, n| "  skipped, #{reason}: #{n}" }
      ]
    end

    def setup_lines
      return [ "Lineups: not run (no setups.csv)" ] if setups_read.nil?

      [
        "Lineups read: #{setups_read}",
        "  imported: #{setups_imported}",
        "  already present (legacy id): #{setups_already_present}",
        "  imported, saved from the away seat (turned round when loaded): #{setups_turned_round}",
        "  imported, not a whole army (never offered): #{setups_not_an_army}",
        *setups_skipped.sort.map { |reason, n| "  skipped, #{reason}: #{n}" }
      ]
    end
  end

  def initialize(users_csv:, matches_csv:, messages_csv: nil, setups_csv: nil, batch_size: BATCH)
    @batch_size = batch_size
    @users_csv = users_csv
    @matches_csv = matches_csv
    @messages_csv = messages_csv
    @setups_csv = setups_csv
    @report = Report.empty
  end

  # insert_all writes its values into the SQL string, so a debug-level SQL log
  # (development's default) would hold every legacy email and message: the run
  # logs no SQL.
  def run
    ActiveRecord::Base.logger.silence(Logger::WARN) do
      ActiveRecord::Base.transaction do
        step("users") { import_users }
        step("matches") { import_matches }
        step("messages") { import_messages } if @messages_csv
        step("setups") { import_setups } if @setups_csv
      end
    end
    @report
  end

  private

  # ---- Failing without a row -------------------------------------------------------

  # Any error in a step but a batch's own becomes a Failed naming the step.
  def step(table)
    yield
  rescue Failed
    raise
  rescue StandardError => e
    raise Failed, "Legacy import failed: importing #{table}, #{e.class.name}. #{ROLLED_BACK}", cause: nil
  end

  # insert_all! in batches; a failed batch is named by its place and the
  # legacy ids it spans, never by its rows.
  def insert_batches(model, records)
    batches = records.each_slice(@batch_size).to_a
    batches.each.with_index(1) do |batch, index|
      model.insert_all!(batch)
    rescue StandardError => e
      ids = batch.map { |record| record[:legacy_id] }
      raise Failed, "Legacy import failed: #{model.table_name} batch #{index} of #{batches.size} " \
                    "(legacy ids #{ids.min}-#{ids.max}), #{e.class.name}. #{ROLLED_BACK}", cause: nil
    end
  end

  # ---- Players -----------------------------------------------------------------

  def import_users
    rows = read(@users_csv).sort_by { |row| row["id"].to_i }
    @report.users_read = rows.size
    present = User.where.not(legacy_id: nil).pluck(:legacy_id).to_set
    taken_names = User.where.not(username: nil).pluck(Arel.sql("lower(username)")).to_set
    taken_emails = User.where.not(email: nil).pluck(Arel.sql("lower(email)")).to_set

    fresh = rows.reject { |row| present.include?(row["id"].to_i) }
    @report.users_already_present = rows.size - fresh.size

    records = fresh.map do |row|
      legacy_id = row["id"].to_i
      {
        legacy_id: legacy_id,
        username: claim_username(row["username"].to_s.strip, legacy_id, taken_names),
        email: claim_email(row["email"], legacy_id, taken_emails),
        wins: row["wins"].to_i,
        losses: row["losses"].to_i,
        created_at: time(row["created_at"]),
        updated_at: time(row["updated_at"]) || time(row["created_at"])
      }
    end
    insert_batches(User, records)
    # Sluggable's name_slug for a nameless player, which a later save would set
    # anyway; insert_all runs no callbacks.
    User.where(legacy_id: records.map { |r| r[:legacy_id] }, slug: nil).update_all("slug = 'user-' || id") if records.any?
    @report.users_imported = records.size
  end

  def claim_username(name, legacy_id, taken)
    name = "player_#{legacy_id}" if name.empty?
    candidate = name
    if taken.include?(candidate.downcase)
      @report.usernames_renamed += 1
      candidate = "#{name}_#{legacy_id}"
      suffix = 1
      candidate = "#{name}_#{legacy_id}_#{suffix += 1}" while taken.include?(candidate.downcase)
    end
    taken << candidate.downcase
    candidate
  end

  def claim_email(raw, legacy_id, taken)
    if COMPUTER_LEGACY_IDS.cover?(legacy_id)
      @report.emails_dropped_computer += 1
      return nil
    end
    email = raw.to_s.strip.downcase.presence
    return nil unless email

    if taken.include?(email)
      @report.emails_dropped_duplicate += 1
      return nil
    end
    taken << email
    email
  end

  # ---- Matches -----------------------------------------------------------------

  def import_matches
    rows = read(@matches_csv)
    @report.matches_read = rows.size
    user_ids = legacy_user_ids
    present = Match.where.not(legacy_id: nil).pluck(:legacy_id).to_set

    records = []
    rows.each do |row|
      if present.include?(row["id"].to_i)
        @report.matches_already_present += 1
        next
      end
      home = user_ids[row["home_user_id"].to_i]
      away = user_ids[row["away_user_id"].to_i]
      unless home && away
        @report.matches_skipped["a player missing from users.csv"] += 1
        next
      end
      if home == away
        @report.matches_skipped["the same player on both sides"] += 1
        next
      end

      winner_seat, reason = outcome(row)
      @report.matches_by_outcome["#{row['match_against']} #{row['match_status']} -> #{reason}"] += 1
      records << match_record(row, home, away, winner_seat, reason)
    end
    insert_batches(Match, records)
    @report.matches_imported = records.size
  end

  # [winning seat (:home, :away or nil), finish_reason]
  def outcome(row)
    return [ nil, "abandoned" ] unless row["match_status"] == Match::FINISHED

    home_king_fell = king_captured?(row["home_units_position"])
    away_king_fell = king_captured?(row["away_units_position"])
    return [ :away, "king" ] if home_king_fell && !away_king_fell
    return [ :home, "king" ] if away_king_fell && !home_king_fell
    return [ nil, "abandoned" ] if home_king_fell || row["match_against"] != "human"
    return [ nil, "expired" ] if row["whos_turn"].blank?

    # whos_turn 1 is home to move: home let the clock run out.
    [ row["whos_turn"].to_i == Match::HOME ? :away : :home, "forfeit" ]
  end

  # "unitIndex:location|" x 19; a captured unit's location is g<team>.
  def king_captured?(position)
    king = position.to_s.split("|").map { |unit| unit.split(":") }.find { |index, _| index.to_i == KING_INDEX }
    king.present? && king[1].to_s.start_with?("g")
  end

  def match_record(row, home, away, winner_seat, reason)
    {
      legacy_id: row["id"].to_i,
      home_user_id: home,
      away_user_id: away,
      turn: integer(row["turn"]),
      who_started: integer(row["who_started"]),
      match_status: Match::FINISHED,
      match_against: row["match_against"],
      home_units_position: row["home_units_position"],
      away_units_position: row["away_units_position"],
      whos_turn: integer(row["whos_turn"]),
      home_ready: boolean(row["home_ready"]),
      away_ready: boolean(row["away_ready"]),
      last_move: row["last_move"],
      time_of_last_move: time(row["time_of_last_move"]),
      utility_saved_hex: row["utility_saved_hex"],
      fast_game: boolean(row["fast_game"]),
      winner_id: { home: home, away: away }[winner_seat],
      finish_reason: reason,
      created_at: time(row["created_at"]),
      updated_at: time(row["updated_at"]) || time(row["created_at"])
    }
  end

  # ---- Messages ----------------------------------------------------------------

  def import_messages
    rows = read(@messages_csv)
    @report.messages_read = rows.size
    user_ids = legacy_user_ids
    # legacy match id -> [id, the pair of players], to keep a match only on a
    # message between its two players.
    matches = Match.where.not(legacy_id: nil).pluck(:legacy_id, :id, :home_user_id, :away_user_id)
                   .to_h { |legacy_id, id, home, away| [ legacy_id, [ id, [ home, away ].sort ] ] }
    present = Message.where.not(legacy_id: nil).pluck(:legacy_id).to_set

    records = []
    rows.each do |row|
      if present.include?(row["id"].to_i)
        @report.messages_already_present += 1
        next
      end
      reason = message_skip_reason(row, user_ids)
      if reason
        @report.messages_skipped[reason] += 1
        next
      end

      sender = user_ids[row["sender"].to_i]
      receiver = user_ids[row["receiver"].to_i]
      match_id, players = matches[row["match"].to_i]
      match_id = nil unless players == [ sender, receiver ].sort
      @report.messages_without_match += 1 if match_id.nil? && row["match"].to_i.positive?
      @report.messages_blank += 1 if row["message"].to_s.strip.empty?
      records << {
        legacy_id: row["id"].to_i,
        message: row["message"],
        sender_id: sender,
        receiver_id: receiver,
        match_id: match_id,
        read: boolean(row["read"]) || false,
        created_at: time(row["created_at"]),
        updated_at: time(row["updated_at"]) || time(row["created_at"])
      }
    end
    insert_batches(Message, records)
    @report.messages_imported = records.size
  end

  def message_skip_reason(row, user_ids)
    sender, receiver = row["sender"].to_i, row["receiver"].to_i
    return "addressed to no player (legacy receiver 0)" if receiver.zero?
    return "sent by no player (legacy sender 0)" if sender.zero?
    return "a sender or receiver missing from users.csv" unless user_ids[sender] && user_ids[receiver]

    "sent to themselves" if sender == receiver
  end

  # ---- Lineups -----------------------------------------------------------------

  def import_setups
    rows = read(@setups_csv)
    @report.setups_read = rows.size
    user_ids = legacy_user_ids
    present = Setup.where.not(legacy_id: nil).pluck(:legacy_id).to_set

    records = []
    rows.each do |row|
      if present.include?(row["id"].to_i)
        @report.setups_already_present += 1
        next
      end
      owner = user_ids[row["user_id"].to_i]
      reason = if owner.nil? then "an owner missing from users.csv"
      elsif row["units_position"].blank? then "no army saved"
      elsif row["button_position"].blank? then "no slot"
      end
      if reason
        @report.setups_skipped[reason] += 1
        next
      end

      count_lineup_shape(row["units_position"])
      records << {
        legacy_id: row["id"].to_i,
        user_id: owner,
        name: row["name"],
        units_position: row["units_position"],
        button_position: row["button_position"].to_i,
        created_at: time(row["created_at"]),
        updated_at: time(row["updated_at"]) || time(row["created_at"])
      }
    end
    insert_batches(Setup, records)
    @report.setups_imported = records.size
  end

  def count_lineup_shape(units_position)
    CyvasseRules::Game.parse_lineup!(units_position)
  rescue CyvasseRules::Game::IllegalMove
    if Setup.new(units_position: units_position).lineup
      @report.setups_turned_round += 1
    else
      @report.setups_not_an_army += 1
    end
  end

  def legacy_user_ids
    User.where.not(legacy_id: nil).pluck(:legacy_id, :id).to_h
  end

  # ---- Reading the export --------------------------------------------------------

  # psql \copy CSV: a header row, empty fields for null, t/f booleans, and
  # timestamps without a zone that Rails 4 wrote in UTC.
  def read(path)
    CSV.read(path, headers: true).map(&:to_h)
  end

  def time(value)
    value.present? ? ActiveSupport::TimeZone["UTC"].parse(value) : nil
  end

  def integer(value)
    value.present? ? value.to_i : nil
  end

  def boolean(value)
    { "t" => true, "true" => true, "f" => false, "false" => false }[value.to_s]
  end
end
