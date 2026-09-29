require "test_helper"
require "rake"

# [unit] The seed is the source of truth for the computer players' portraits
# (task cyvasse-bot-portraits): User.seed_computer_players!, called by
# db/seeds.rb and by the users:seed_computer_players post-deploy task, creates
# any missing named computer player and sets each one's portrait in place, and
# a second run changes nothing.
class UserComputerPortraitsTest < ActiveSupport::TestCase
  EXPECTED = { "qavo" => 2, "tyrion" => 3, "haldon" => 4, "doran" => 5, "ben" => 6, "aegon" => 7 }.freeze

  def portraits
    User.where(legacy_id: EXPECTED.values).order(:legacy_id).pluck(:username, :portrait).to_h
  end

  test "every named computer player has a portrait file in the asset path" do
    assert_equal EXPECTED.keys.sort, User::COMPUTER_PORTRAITS.keys.sort
    User::COMPUTER_PORTRAITS.each do |username, path|
      assert_equal "bots/#{username}.webp", path
      asset = Rails.application.assets.load_path.find(path)
      assert asset, "#{path} is missing"
      assert_equal "RIFF", File.binread(asset.path, 4), "#{path} is a WebP"
      assert_operator File.size(asset.path), :<, 40_000, "#{path} stays small"
    end
  end

  test "a fresh database gets all six computer players with their portraits" do
    assert_difference -> { User.count }, 6 do
      User.seed_computer_players!
    end
    assert_equal EXPECTED.keys.index_with { |u| "bots/#{u}.webp" }, portraits
    assert User.find_by(legacy_id: 4).computer?
    assert_equal "Haldon Halfmaester", User.find_by(legacy_id: 4).name
  end

  test "an imported computer player is updated in place, and nothing else is touched" do
    imported = User.create!(legacy_id: 4, username: "haldon") # LegacyImport: no name, no portrait
    person = User.create!(email: "arya@example.test", name: "Arya", username: "arya")
    alexx = User.create!(legacy_id: 8, username: "alexx", name: "alexx mcritchie")

    assert_difference -> { User.count }, 5 do
      User.seed_computer_players!
    end
    assert_equal "bots/haldon.webp", imported.reload.portrait
    assert_nil imported.name, "the seed sets the portrait only"
    assert_nil person.reload.portrait
    assert_nil alexx.reload.portrait
  end

  test "a second run writes nothing, and a drifted portrait is put back" do
    User.seed_computer_players!
    stamps = User.where(legacy_id: EXPECTED.values).pluck(:id, :updated_at).to_h

    assert_no_difference -> { User.count } do
      User.seed_computer_players!
    end
    assert_equal stamps, User.where(legacy_id: EXPECTED.values).pluck(:id, :updated_at).to_h

    User.find_by(legacy_id: 2).update_columns(portrait: nil)
    User.seed_computer_players!
    assert_equal "bots/qavo.webp", User.find_by(legacy_id: 2).portrait
  end

  test "the computer a live match seats has its portrait even without a seed run" do
    arya = User.create!(email: "arya@example.test", name: "Arya", username: "arya")
    bot = Match.start_live!(arya, computer: true, rng: Random.new(4)).away_user
    assert_equal "bots/#{bot.username}.webp", bot.portrait
  end

  test "db/seeds.rb seeds the portraits, twice over" do
    2.times { assert_output(/Seeded computer: haldon \(bots\/haldon\.webp\)/) { load Rails.root.join("db/seeds.rb") } }
    assert_equal EXPECTED.keys.index_with { |u| "bots/#{u}.webp" }, portraits
  end

  test "users:seed_computer_players is the narrow post-deploy task" do
    Rails.application.load_tasks unless Rake::Task.task_defined?("users:seed_computer_players")
    task = Rake::Task["users:seed_computer_players"]
    task.reenable
    assert_output(/Seeded computer: aegon \(bots\/aegon\.webp\)/) { task.invoke }
    task.reenable
    assert_no_difference -> { User.count } do
      assert_output(/Seeded computer: qavo/) { task.invoke }
    end
    assert_equal 6, User.where.not(portrait: nil).count
    assert_equal 0, User.where(email: User::SEED_IDENTITIES.map { |i| i[:email] }).count, "no identities from this task"
  end

  test "a portrait must be a path under bots/" do
    user = User.new(legacy_id: 9, username: "alexxx", portrait: "../../config/master.key")
    assert_not user.valid?
    assert_includes user.errors[:portrait], "is invalid"
  end
end
