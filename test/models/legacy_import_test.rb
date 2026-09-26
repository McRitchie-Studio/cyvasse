require "test_helper"

# [unit] LegacyImport on small synthetic CSVs (test/fixtures/files/legacy/,
# never the real export): column mapping, the duplicate-name and email rules,
# the derived winners, closing unfinished matches, and skipping what cannot
# import.
class LegacyImportTest < ActiveSupport::TestCase
  DIR = Rails.root.join("test/fixtures/files/legacy")

  setup do
    # Players of the new app who got there first.
    @namesake = User.create!(email: "namesake@example.test", name: "Name Sake", username: "Taken_Name")
    @member = User.create!(email: "member@example.test", name: "Member")
    @report = import
  end

  test "imports every player with username, record and joined date, and keeps the legacy id" do
    assert_equal 10, @report.users_read
    assert_equal 10, @report.users_imported
    assert_equal [ 1, 2, 3, 11, 12, 13, 14, 15, 16, 17 ], User.where.not(legacy_id: nil).order(:legacy_id).pluck(:legacy_id)

    rook = legacy_user(11)
    assert_equal "Rook", rook.username
    assert_equal [ 5, 3 ], [ rook.wins, rook.losses ]
    assert_equal Time.utc(2015, 1, 2, 3, 4, 5.123456r), rook.created_at
    assert_equal "rook@example.test", rook.email
    assert_equal "viewer", rook.role
    assert_nil rook.name
    assert_equal "user-#{rook.id}", rook.slug
    assert_equal "Rook", rook.display_name
  end

  test "never carries the password digest or admin rights over" do
    refute_includes User.column_names, "password_digest"
    values = User.where.not(legacy_id: nil).flat_map { |u| u.attributes.values }.map(&:to_s)
    assert values.none? { |v| v.include?("SYNTHETICdigest") }, "a password digest reached the users table"
    assert_equal "viewer", legacy_user(1).role
  end

  test "the earliest account keeps a name that collides in any case or once trimmed; later ones get the legacy id" do
    assert_equal "Rook", legacy_user(11).username
    assert_equal "rook_12", legacy_user(12).username
    assert_equal "Rook_13", legacy_user(13).username
    assert_equal "Bishop", legacy_user(14).username
    # A name a player of the new app already holds stays theirs.
    assert_equal "taken_name_15", legacy_user(15).username
    assert_equal "Taken_Name", @namesake.reload.username
    assert_equal 3, @report.usernames_renamed
    assert_equal legacy_user(11), User.find_by_username("ROOK")
  end

  test "emails are trimmed and downcased; a shared one goes to the earliest account" do
    assert_equal "rook.two@example.test", legacy_user(12).email
    assert_equal "pawn@example.test", legacy_user(16).email
    assert_nil legacy_user(14).email, "a later account sharing an email imports without one"
    assert_nil legacy_user(17).email, "an email a new-app player holds stays theirs"
    assert_equal @member, User.find_by(email: "member@example.test")
    assert_equal 2, @report.emails_dropped_duplicate
  end

  test "computer opponents import with no email; legacy id 1 is an ordinary player" do
    assert_nil legacy_user(2).email
    assert_nil legacy_user(3).email
    assert_equal "oldadmin@example.test", legacy_user(1).email
    assert_equal 2, @report.emails_dropped_computer
  end

  test "finished matches import with their players and the winner the legacy code decided" do
    rook, pawn = legacy_user(11), legacy_user(16)

    king = legacy_match(101)
    assert_equal [ rook, pawn ], [ king.home_user, king.away_user ]
    assert_equal [ pawn, "king" ], [ king.winner, king.finish_reason ], "home king in the graveyard: away won"
    assert_equal [ rook, "king" ], [ legacy_match(102).winner, legacy_match(102).finish_reason ]
    assert_equal [ rook, "forfeit" ], [ legacy_match(103).winner, legacy_match(103).finish_reason ],
                 "home (pawn) was on the move when the clock ran out"
    assert_equal [ nil, "expired" ], [ legacy_match(104).winner, legacy_match(104).finish_reason ]
    assert_equal [ rook, "king" ], [ legacy_match(105).winner, legacy_match(105).finish_reason ]
    assert_equal [ nil, "abandoned" ], [ legacy_match(106).winner, legacy_match(106).finish_reason ],
                 "a computer match with no king taken has no known result"
  end

  test "every legacy column comes over verbatim" do
    match = legacy_match(101)
    assert_equal 31, match.turn
    assert_equal 1, match.who_started
    assert_equal "human", match.match_against
    assert_equal "1:60|17:g1|", match.home_units_position
    assert_equal "1:20|17:5|", match.away_units_position
    assert_equal 1, match.whos_turn
    assert_equal [ true, true ], [ match.home_ready, match.away_ready ]
    assert_equal "12,5", match.last_move
    assert_equal "95", match.utility_saved_hex
    assert_nil match.fast_game
    assert_equal Time.utc(2015, 2, 2), match.time_of_last_move
    assert_equal Time.utc(2015, 2, 1), match.created_at
    assert_equal Time.utc(2015, 2, 2), match.updated_at
  end

  test "unfinished matches close as abandoned with no winner, and no record changes" do
    [ 107, 108, 109 ].each do |id|
      match = legacy_match(id)
      assert_equal [ Match::FINISHED, "abandoned", nil ], [ match.match_status, match.finish_reason, match.winner_id ], "legacy match #{id}"
    end
    assert_equal 7, legacy_match(107).turn, "the board as it was left"
    assert_equal({ 11 => [ 5, 3 ], 16 => [ 4, 1 ], 2 => [ 40, 60 ] },
                 [ 11, 16, 2 ].to_h { |id| [ id, [ legacy_user(id).wins, legacy_user(id).losses ] ] })
    assert Match.where.not(legacy_id: nil).all?(&:valid?)
  end

  test "the seven-day clock never touches an imported match" do
    assert_no_changes -> { Match.order(:id).pluck(:match_status, :winner_id, :finish_reason, :updated_at) } do
      Match.expire_stale!
    end
    assert_empty Match.active.where.not(legacy_id: nil)
  end

  test "a match whose player is missing is skipped and counted, and the outcomes are counted" do
    assert_equal 10, @report.matches_read
    assert_equal 9, @report.matches_imported
    assert_nil Match.find_by(legacy_id: 110)
    assert_equal({ "a player missing from users.csv" => 1 }, @report.matches_skipped)
    assert_equal({ "computer finished -> abandoned" => 1, "computer finished -> king" => 1, "computer new -> abandoned" => 1,
                   "human finished -> expired" => 1, "human finished -> forfeit" => 1, "human finished -> king" => 2,
                   "human in progress -> abandoned" => 1, "human pending -> abandoned" => 1 }, @report.matches_by_outcome)
  end

  test "the report is counts only" do
    text = @report.lines.join("\n")
    refute_match(/@|rook|SYNTHETIC/i, text)
    assert_match(/Users read: 10/, text)
  end

  private

  def import
    LegacyImport.new(users_csv: DIR.join("users.csv"), matches_csv: DIR.join("matches.csv")).run
  end

  def legacy_user(id) = User.find_by!(legacy_id: id)
  def legacy_match(id) = Match.find_by!(legacy_id: id)
end
