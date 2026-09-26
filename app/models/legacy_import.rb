# Imports the players and matches of the old Cyvasse (the personal Heroku app
# cyvasse-game, 2014-2023) from the CSV export of its database: epic
# cyvasse-revival piece 10a. `bin/rails legacy:import` runs it.
#
#   LegacyImport.new(users_csv: path, matches_csv: path).run  # => LegacyImport::Report
#
# The CSVs hold emails and password hashes: never commit them or print a row.
# The importer reads only the columns below; the password digest (and every
# other profile column) is never read, so it cannot land here. The Report
# carries counts only.
#
# Idempotent. Every row keeps its old id in `legacy_id`, and a rerun inserts
# only the legacy ids not yet present; it never updates a row it finds, so a
# second run changes nothing. It runs in one transaction: a failure leaves
# nothing half-imported.
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
require "csv"

class LegacyImport
  COMPUTER_LEGACY_IDS = User::COMPUTER_LEGACY_IDS
  KING_INDEX = 17
  BATCH = 1_000

  # Counts only; never a row.
  Report = Struct.new(:users_read, :users_imported, :users_already_present, :usernames_renamed,
                      :emails_dropped_duplicate, :emails_dropped_computer, :matches_read, :matches_imported,
                      :matches_already_present, :matches_by_outcome, :matches_skipped, keyword_init: true) do
    def self.empty
      new(users_read: 0, users_imported: 0, users_already_present: 0, usernames_renamed: 0,
          emails_dropped_duplicate: 0, emails_dropped_computer: 0, matches_read: 0, matches_imported: 0,
          matches_already_present: 0, matches_by_outcome: Hash.new(0), matches_skipped: Hash.new(0))
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
        *matches_skipped.sort.map { |reason, n| "  skipped, #{reason}: #{n}" }
      ]
    end
  end

  def initialize(users_csv:, matches_csv:)
    @users_csv = users_csv
    @matches_csv = matches_csv
    @report = Report.empty
  end

  # insert_all writes its values into the SQL string, so a debug-level SQL log
  # (development's default) would hold every legacy email: the run logs no SQL.
  def run
    ActiveRecord::Base.logger.silence(Logger::WARN) do
      ActiveRecord::Base.transaction do
        import_users
        import_matches
      end
    end
    @report
  end

  private

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
    records.each_slice(BATCH) { |batch| User.insert_all!(batch) }
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
    user_ids = User.where.not(legacy_id: nil).pluck(:legacy_id, :id).to_h
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
    records.each_slice(BATCH) { |batch| Match.insert_all!(batch) }
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
