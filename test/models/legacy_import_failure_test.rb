require "test_helper"

# [unit] A legacy import that fails partway prints no row. Postgres puts the
# failing row in its error ("Failing row contains (...)", "Key (email)=(...)")
# and ActiveRecord adds the whole INSERT with every value, so the error a
# failed batch raises would carry emails and private message text to the
# operator's terminal. LegacyImport::Failed names only the table, the batch,
# the legacy id range and the error's class, drops the original as its cause,
# and the whole run still rolls back.
#
# Each test forces a real insert failure with a CHECK constraint that one
# synthetic row breaks (NOT VALID, so the fixture rows already in the table
# are not checked); the test transaction drops it again.
class LegacyImportFailureTest < ActiveSupport::TestCase
  include LegacyFixtureValues

  DIR = LegacyFixtureValues::DIR

  test "a failed users batch names the table, the batch and its legacy ids, and no row" do
    # Sorted by legacy id in threes: 1-3, 11-13, 14-16, 17. Pawn is 16.
    reject_row "users", "email IS DISTINCT FROM 'pawn@example.test'"
    error = assert_import_fails
    assert_equal "Legacy import failed: users batch 3 of 4 (legacy ids 14-16), #{check_violation}. " \
                 "Nothing was imported: the whole run rolled back. The database's message is withheld " \
                 "because it quotes row values.", error.message
  end

  test "a failed matches batch is redacted" do
    reject_row "matches", "home_units_position IS DISTINCT FROM '1:60|17:g1|'"
    assert_match(/\ALegacy import failed: matches batch 1 of 3 \(legacy ids 101-103\), /, assert_import_fails.message)
  end

  test "a failed messages batch prints no message text and rolls back the players and matches" do
    # Imported 201-203, 206-208, 209-210.
    reject_row "messages", "message IS DISTINCT FROM 'SYNTHETIC wrong match'"
    assert_match(/\ALegacy import failed: messages batch 3 of 3 \(legacy ids 209-210\), /, assert_import_fails.message)
    assert_equal 0, User.where.not(legacy_id: nil).count + Match.where.not(legacy_id: nil).count +
                    Message.where.not(legacy_id: nil).count, "one transaction: nothing stays half-imported"
  end

  test "a failed board posts batch prints no post and rolls back the messages" do
    # Imported 204, 212, 215: one batch.
    reject_row "board_posts", "message IS DISTINCT FROM 'SYNTHETIC board reply'"
    assert_match(/\ALegacy import failed: board_posts batch 1 of 1 \(legacy ids 204-215\), /, assert_import_fails.message)
    assert_equal 0, Message.where.not(legacy_id: nil).count + BoardPost.count, "one transaction: nothing stays half-imported"
  end

  test "a failed lineups batch is redacted" do
    reject_row "setups", "name IS DISTINCT FROM 'SYNTH Old'"
    assert_match(/\ALegacy import failed: setups batch 1 of 2 \(legacy ids 301-303\), /, assert_import_fails.message)
  end

  test "a failure outside a batch insert names only the step" do
    # The slug backfill after the users insert breaks it.
    reject_row "users", "slug IS NULL OR slug NOT LIKE 'user-%'"
    error = assert_import_fails
    assert_equal "Legacy import failed: importing users, #{check_violation}. Nothing was imported: the whole " \
                 "run rolled back. The database's message is withheld because it quotes row values.", error.message
  end

  test "the raw database error would have leaked a row" do
    reject_row "messages", "message IS DISTINCT FROM 'SYNTHETIC wrong match'"
    raw = assert_raises(ActiveRecord::StatementInvalid) do
      ActiveRecord::Base.transaction(requires_new: true) do
        Message.insert_all!([ { legacy_id: 1, message: "SYNTHETIC wrong match", sender_id: 0,
                                receiver_id: 0, read: false, created_at: Time.current, updated_at: Time.current } ])
      end
    end
    assert_includes raw.message, "SYNTHETIC wrong match", "the control: the unredacted error quotes the row"
  end

  private

  def reject_row(table, condition)
    ActiveRecord::Base.connection.execute(
      "ALTER TABLE #{table} ADD CONSTRAINT legacy_import_failure_test CHECK (#{condition}) NOT VALID"
    )
  end

  # Runs the import in batches of three and returns the error, having checked
  # that nothing it or its causes print carries a fixture value.
  def assert_import_fails
    error = assert_raises(LegacyImport::Failed) do
      LegacyImport.new(users_csv: DIR.join("users.csv"), matches_csv: DIR.join("matches.csv"),
                       messages_csv: DIR.join("messages.csv"), setups_csv: DIR.join("setups.csv"), batch_size: 3).run
    end
    assert_nil error.cause, "a cause is printed under the error (\"Caused by\"), so the original must not ride along"
    # The backtrace's app path is the checkout's, not a row: a desk named
    # admin-legacy-message-board would match the fixture value "Admin".
    refute_legacy_values(error.full_message(highlight: false).gsub(Rails.root.to_s, "<root>"))
    error
  end

  def check_violation
    "ActiveRecord::CheckViolation"
  end
end
