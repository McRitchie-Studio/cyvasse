require "test_helper"

# [component] The sign-in email's HTML, rendered whole through its layout and
# compared with a committed snapshot (test/snapshots/user_mailer/), so any
# change to what a player's inbox receives shows up in review as a diff of
# that file. The one-time token is the only thing that varies, and it is
# pinned. To accept a deliberate change:
#   UPDATE_SNAPSHOTS=1 bin/rails test test/views/sign_in_email_snapshot_test.rb
class SignInEmailSnapshotTest < ActionMailer::TestCase
  include MailHosts

  SNAPSHOTS = Rails.root.join("test/snapshots/user_mailer")

  setup do
    User.create!(email: "veyjin@example.com", name: "Veyjin Stark", username: "veyjin")
  end

  def rendered(part)
    with_hosts(email: "cyvasse.mcritchie.studio") do
      UserMailer.magic_link("veyjin@example.com", "TOKEN0123456789a").public_send(part).body.to_s
    end
  end

  def assert_snapshot(name, actual)
    path = SNAPSHOTS.join(name)
    if ENV["UPDATE_SNAPSHOTS"] == "1"
      path.write(actual)
      skip "snapshot #{name} rewritten"
    end

    assert path.exist?, "no snapshot at #{path}; write it with UPDATE_SNAPSHOTS=1"
    assert_equal path.read, actual, "the sign-in email changed; review the diff and UPDATE_SNAPSHOTS=1 if it is meant"
  end

  test "the HTML part matches its snapshot" do
    assert_snapshot "magic_link.html", rendered(:html_part)
  end

  test "the plain-text part matches its snapshot" do
    assert_snapshot "magic_link.txt", rendered(:text_part)
  end

  test "the snapshot itself is the design asked for: a heading, one button, the plain link, no image" do
    document = Nokogiri::HTML(SNAPSHOTS.join("magic_link.html").read)

    assert_equal "Hi veyjin, here's your Cyvasse sign-in link", document.at_css("h1").text.strip
    assert_equal 1, document.css("td[bgcolor] a").size, "one button"
    assert_equal [ "https://cyvasse.mcritchie.studio/l/TOKEN0123456789a" ] * 2,
                 document.css("a").map { |a| a["href"] }.select { |href| href.include?("/l/") }
    assert_empty document.css("img")
    assert_equal "Cyvasse · cyvasse.mcritchie.studio", document.css("td").last.text.squish
  end
end
