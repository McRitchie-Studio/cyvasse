require "test_helper"

# [unit] LegacyImport's messages and lineups (piece 10b) on small synthetic
# CSVs (test/fixtures/files/legacy/, never the real export): each row mapped
# to its people and match through their legacy ids, orphans skipped and
# counted, the legacy columns kept, a rerun changing nothing, and no message
# text in the SQL log or the report.
class LegacyImportMessagesAndLineupsTest < ActiveSupport::TestCase
  DIR = Rails.root.join("test/fixtures/files/legacy")

  setup { @report = import }

  # ---- Messages --------------------------------------------------------------

  test "a message maps its sender, receiver and match through their legacy ids and keeps every column" do
    message = legacy_message(201)
    assert_equal [ legacy_user(11), legacy_user(16) ], [ message.sender, message.receiver ]
    assert_equal legacy_match(101), message.match
    assert_equal "SYNTHETIC good game", message.message
    assert message.read
    assert_equal Time.utc(2015, 2, 1, 10), message.created_at
    assert_equal Time.utc(2015, 2, 1, 11), message.updated_at
  end

  test "blank text, a null read, a comma and a line break come over as they were" do
    assert_equal "", legacy_message(202).message
    assert_equal Time.utc(2015, 2, 1, 10, 5, 0.123456r), legacy_message(202).created_at
    refute legacy_message(207).read, "a legacy null read imports as unread"
    assert_equal legacy_message(207).created_at, legacy_message(207).updated_at
    assert_equal "SYNTHETIC line one, still\nline two", legacy_message(210).message
    assert_equal 1, @report.messages_blank
  end

  test "a message to a computer opponent imports; so does one sent outside any match" do
    assert_equal legacy_user(2), legacy_message(203).receiver
    assert_nil legacy_message(207).match
  end

  test "a message whose match was not imported, or is not between its two people, keeps its conversation without it" do
    [ 206, 208, 209 ].each { |id| assert_nil legacy_message(id).match, "legacy message #{id}" }
    assert_equal legacy_match(104), legacy_message(210).match
    assert_equal 3, @report.messages_without_match
  end

  test "a message with nobody, or a missing player, at either end is skipped and counted" do
    assert_equal 16, @report.messages_read
    assert_equal 8, @report.messages_imported
    [ 204, 205, 211, 212, 213, 214, 215, 216 ].each { |id| assert_nil Message.find_by(legacy_id: id), "legacy message #{id}" }
    assert_equal({ "addressed to no player (legacy receiver 0)" => 1, "a sender or receiver missing from users.csv" => 1,
                   "sent to themselves" => 1, LegacyImport::BOARD_POST => 5 }, @report.messages_skipped)
  end

  test "imported messages read in the inbox and the admin page as any other" do
    rook = legacy_user(11)
    page = Conversation.page(Message.visible_to(rook), reader: rook)
    assert_equal 3, page.total, "Rook talks with Pawn, Bishop and a computer"
    assert_equal 1, Message.unread_by(rook).count
  end

  # ---- Lineups ---------------------------------------------------------------

  test "a lineup comes to its owner with its name, army, slot and dates" do
    wall = legacy_setup(301)
    assert_equal legacy_user(11), wall.user
    assert_equal "SYNTH Wall", wall.name
    assert_equal 1, wall.button_position
    assert_equal army(52..70), wall.units_position
    assert_equal army(52..70), wall.lineup
    assert_equal Time.utc(2015, 1, 10), wall.created_at
    assert_equal legacy_setup(304).created_at, legacy_setup(304).updated_at, "a null updated_at takes the created_at"
  end

  test "a lineup saved from the away seat is turned round; one that is not an army is kept but never offered" do
    away = legacy_setup(304)
    assert_equal army(1..19), away.units_position, "stored verbatim"
    assert_equal army((73..91).to_a.reverse), away.lineup
    assert_nil legacy_setup(305).lineup
    assert_equal 1, @report.setups_turned_round
    assert_equal 1, @report.setups_not_an_army
  end

  test "a lineup whose owner is missing is skipped; a nameless one imports" do
    assert_equal 7, @report.setups_read
    assert_equal 6, @report.setups_imported
    assert_nil Setup.find_by(legacy_id: 306)
    assert_equal({ "an owner missing from users.csv" => 1 }, @report.setups_skipped)
    assert_equal "", legacy_setup(307).name.to_s
  end

  test "the newest lineup in a slot is the one a player sees" do
    slots = Setup.slots_for(legacy_user(11))
    assert_equal [ "SYNTH Wall", "SYNTH New", nil ], slots.values.map { |setup| setup&.name }
  end

  # ---- Idempotence and privacy -----------------------------------------------

  test "a rerun imports nothing and changes no row" do
    before = snapshot
    rerun = import
    assert_equal [ 0, 8 ], [ rerun.messages_imported, rerun.messages_already_present ]
    assert_equal [ 0, 6 ], [ rerun.setups_imported, rerun.setups_already_present ]
    assert_equal before, snapshot
  end

  test "the SQL log never carries a message or a lineup name, even at debug level" do
    [ BoardPost, Message, Setup, Match, User ].each { |model| model.where.not(legacy_id: nil).delete_all }
    io = StringIO.new
    saved, ActiveRecord::Base.logger = ActiveRecord::Base.logger, ActiveSupport::Logger.new(io, level: :debug)
    import
    refute_match(/SYNTH|@example/i, io.string, "insert_all inlines its values; a debug log would hold every message")
  ensure
    ActiveRecord::Base.logger = saved
  end

  test "the report is counts only" do
    text = @report.lines.join("\n")
    refute_match(/SYNTH|@|rook/i, text)
    assert_match(/Messages read: 16\n  imported: 8\n/, text)
    assert_match(/Lineups read: 7\n  imported: 6\n/, text)
  end

  test "left out, messages and lineups are not run" do
    Message.delete_all
    Setup.delete_all
    report = LegacyImport.new(users_csv: DIR.join("users.csv"), matches_csv: DIR.join("matches.csv")).run
    assert_nil report.messages_read
    assert_includes report.lines, "Messages: not run (no messages.csv)"
    assert_equal 0, Message.count + Setup.count
  end

  private

  def import
    LegacyImport.new(users_csv: DIR.join("users.csv"), matches_csv: DIR.join("matches.csv"),
                     messages_csv: DIR.join("messages.csv"), setups_csv: DIR.join("setups.csv")).run
  end

  def snapshot
    [ Message, Setup, Match, User ].map { |model| model.order(:id).map(&:attributes) }
  end

  def army(hexes) = hexes.to_a.each_with_index.map { |hex, i| "#{i + 1}:#{hex}|" }.join
  def legacy_user(id) = User.find_by!(legacy_id: id)
  def legacy_match(id) = Match.find_by!(legacy_id: id)
  def legacy_message(id) = Message.find_by!(legacy_id: id)
  def legacy_setup(id) = Setup.find_by!(legacy_id: id)
end
