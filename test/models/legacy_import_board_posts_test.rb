require "test_helper"

# [unit] LegacyImport's public message-board posts (piece 15) on the
# synthetic CSVs (test/fixtures/files/legacy/messages.csv, never the real
# export). A board post is a legacy messages row with receiver 0 and match 0:
# it imports to board_posts, its author mapped through users.legacy_id, and
# never to messages. Every row is accounted for: imported, already present,
# or skipped with a counted reason. A rerun changes nothing, and neither the
# SQL log nor the report carries a post's text.
class LegacyImportBoardPostsTest < ActiveSupport::TestCase
  DIR = Rails.root.join("test/fixtures/files/legacy")

  setup { @report = import }

  test "a board post maps its author through their legacy id and keeps its text and dates" do
    post = BoardPost.find_by!(legacy_id: 204)
    assert_equal User.find_by!(legacy_id: 11), post.user
    assert_equal "SYNTHETIC board post", post.message
    assert_equal Time.utc(2015, 5, 2), post.created_at
    assert_equal Time.utc(2015, 5, 2), post.updated_at

    reply = BoardPost.find_by!(legacy_id: 215)
    assert_equal User.find_by!(legacy_id: 14), reply.user
    assert_equal reply.created_at, reply.updated_at, "a null updated_at takes the created_at"
  end

  test "every board row is imported or skipped with a counted reason; none is silent" do
    assert_equal 5, @report.board_posts_read
    assert_equal 3, @report.board_posts_imported
    assert_equal [ 204, 212, 215 ], BoardPost.order(:legacy_id).pluck(:legacy_id)
    assert_equal({ "an author missing from users.csv" => 1, "posted by no player (legacy sender 0)" => 1 },
                 @report.board_posts_skipped)
    assert_equal @report.board_posts_read,
                 @report.board_posts_imported + @report.board_posts_already_present + @report.board_posts_skipped.values.sum
  end

  test "a blank board post is imported, counted, and not shown" do
    blank = BoardPost.find_by!(legacy_id: 212)
    assert_equal "   ", blank.message
    assert_equal 1, @report.board_posts_blank
    assert_equal [ blank ], BoardPost.blank_text.to_a
    assert_not_includes BoardPost.with_text, blank
    assert_equal 2, BoardPost.page(1).total
  end

  test "board posts never land in messages; receiver 0 outside the board is still skipped" do
    assert_nil Message.find_by(legacy_id: [ 204, 212, 213, 214, 215, 216 ])
    assert_equal 5, @report.messages_skipped[LegacyImport::BOARD_POST]
    assert_equal 1, @report.messages_skipped["addressed to no player (legacy receiver 0)"]
    rook = User.find_by!(legacy_id: 11)
    assert_equal 3, Conversation.page(Message.visible_to(rook), reader: rook).total, "no board conversation"
  end

  test "a rerun imports nothing and changes no board post" do
    before = BoardPost.order(:id).map(&:attributes)
    rerun = import
    assert_equal [ 5, 0, 3 ], [ rerun.board_posts_read, rerun.board_posts_imported, rerun.board_posts_already_present ]
    assert_equal before, BoardPost.order(:id).map(&:attributes)
  end

  test "the report counts board posts and carries no text" do
    text = @report.lines.join("\n")
    assert_match(/Board posts read \(legacy receiver 0, match 0\): 5\n  imported: 3\n  already present \(legacy id\): 0\n  imported with blank text \(never shown\): 1\n/, text)
    refute_match(/SYNTH/i, text)
  end

  test "left out, messages.csv takes the board posts with it" do
    BoardPost.delete_all
    report = LegacyImport.new(users_csv: DIR.join("users.csv"), matches_csv: DIR.join("matches.csv")).run
    assert_nil report.board_posts_read
    assert_includes report.lines, "Board posts: not run (no messages.csv)"
    assert_equal 0, BoardPost.count
  end

  test "the SQL log never carries a board post, even at debug level" do
    [ BoardPost, Message, Setup, Match, User ].each { |model| model.where.not(legacy_id: nil).delete_all }
    io = StringIO.new
    saved, ActiveRecord::Base.logger = ActiveRecord::Base.logger, ActiveSupport::Logger.new(io, level: :debug)
    import
    refute_match(/SYNTHETIC board/i, io.string)
  ensure
    ActiveRecord::Base.logger = saved
  end

  private

  def import
    LegacyImport.new(users_csv: DIR.join("users.csv"), matches_csv: DIR.join("matches.csv"),
                     messages_csv: DIR.join("messages.csv"), setups_csv: DIR.join("setups.csv")).run
  end
end
