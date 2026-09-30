require "test_helper"

# [unit] The sign-in email Cyvasse owns (app/mailers/user_mailer.rb, task
# trustworthy-sign-in-email): a plain subject, the player's username in the
# greeting and never a role, every URL on the email link host and never on
# cyvasse.xyz, no images, and a plain-text part as good as the HTML.
class UserMailerTest < ActionMailer::TestCase
  include MailHosts

  setup do
    @veyjin = User.create!(email: "veyjin@example.com", name: "Veyjin Stark", username: "veyjin")
  end

  def sign_in_mail(email = @veyjin.email)
    UserMailer.magic_link(email, Studio::Link.create_magic_link(email: email).token)
  end

  def parts(mail) = [ mail.html_part.body.to_s, mail.text_part.body.to_s ]

  test "the app's own mailer sends the sign-in link, not the engine's" do
    assert_equal Rails.root.join("app/mailers/user_mailer.rb").to_s,
                 UserMailer.instance_method(:magic_link).source_location.first
  end

  test "the subject is plain" do
    assert_equal "Your Cyvasse sign-in link", sign_in_mail.subject
  end

  test "the greeting names the player by username, in both parts" do
    html, text = parts(sign_in_mail)
    assert_includes html, "Hi veyjin, here's your Cyvasse sign-in link"
    assert_includes text, "Hi veyjin, here's your Cyvasse sign-in link."
  end

  test "an address with no account gets a greeting that names no one" do
    html, text = parts(sign_in_mail("newcomer@example.com"))
    assert_includes html, "Here's your Cyvasse sign-in link"
    assert_includes text, "Here's your Cyvasse sign-in link."
    refute_match(/\bHi\b/, text)
  end

  test "an admin is never greeted as admin, nor by any role word" do
    # "admin" is reserved for anyone choosing a name (User::RESERVED_USERNAMES),
    # so the holder is written as an imported legacy name arrives, unvalidated.
    admin = User.create!(email: "root@example.com", name: "Admin", role: "admin")
    admin.update_column(:username, "admin")
    parts(sign_in_mail(admin.email)).each do |body|
      refute_match(/admin/i, body, "no role word anywhere in the sign-in email")
    end

    named_admin = User.create!(email: "boss@example.com", name: "Boss", username: "stannis", role: "admin")
    html, = parts(sign_in_mail(named_admin.email))
    assert_includes html, "Hi stannis,"
    refute_match(/admin/i, html)
  end

  test "a Play Now guest is not greeted as Guest_1234" do
    guest = User.create!(email: "guest@example.com", username: "Guest_1234", guest: true)
    refute_includes sign_in_mail(guest.email).text_part.body.to_s, "Guest_1234"
  end

  test "the link and the why-line use the email link host from config" do
    with_hosts(email: "cyvasse.mcritchie.studio") do
      mail = sign_in_mail
      token = Studio::Link.magic_links.order(:created_at).last.token
      parts(mail).each do |body|
        assert_includes body, "https://cyvasse.mcritchie.studio/l/#{token}"
        assert_includes body, "asked to sign in to Cyvasse at cyvasse.mcritchie.studio"
        assert_equal [ "cyvasse.mcritchie.studio" ], hosts_in(body)
      end
    end
  end

  test "with no canonical host set, nothing in the email names cyvasse.xyz" do
    with_hosts(canonical: nil, email: nil) do
      parts(sign_in_mail).each { |body| refute_includes body, "cyvasse.xyz" }
    end
  end

  test "with the canonical host on cyvasse.xyz, the email still links the established host only" do
    with_hosts(canonical: "cyvasse.xyz", email: "cyvasse.mcritchie.studio") do
      parts(sign_in_mail).each do |body|
        refute_includes body, "cyvasse.xyz"
        assert_equal [ "cyvasse.mcritchie.studio" ], hosts_in(body)
      end
    end
  end

  test "one modest button, the plain link under it, and no images at all" do
    html = sign_in_mail.html_part.body.to_s
    document = Nokogiri::HTML(html)
    magic_links = document.css("a").select { |a| a["href"].include?("/l/") }

    assert_equal 2, magic_links.size, "the button and the plain link"
    assert_equal magic_links.first["href"], magic_links.last.text.strip, "the plain link shows the address it opens"
    assert_empty document.css("img"), "no hero, banner or logo"
    refute_match(/background(-image)?\s*[:=]\s*["']?url|\.gif/i, html)
  end

  test "the body carries no spam tokens: no urgency, no shouting, no emoji" do
    parts(sign_in_mail).each do |body|
      text = Nokogiri::HTML(body).text
      refute_match(/\b(urgent|immediately|act now|verify your account|expires in)\b/i, text)
      refute_match(/\b[A-Z]{4,}\b/, text, "no all-caps words")
      refute_match(/\p{Extended_Pictographic}/, text, "no emoji")
    end
  end

  test "it says why it came and what to do if it was not asked for" do
    parts(sign_in_mail).each do |body|
      text = CGI.unescapeHTML(body)
      assert_includes text, "Someone, hopefully you, asked to sign in to Cyvasse"
      assert_includes text, "Didn't ask to sign in? You can ignore this email."
    end
  end

  test "the plain-text part is present, links the token and signs off with the site" do
    mail = sign_in_mail
    token = Studio::Link.magic_links.order(:created_at).last.token

    assert mail.multipart?
    text = mail.text_part.body.to_s
    assert_match %r{^http://example\.com/l/#{token}$}, text, "the link sits on a line of its own"
    assert_match(/^Cyvasse · example\.com$/, text)
  end

  test "the engine's delivery path queues this mailer and renders it from the outbox row" do
    Studio::Email.deliver(UserMailer, :magic_link, @veyjin.email, "tok", to: @veyjin.email)
    delivery = Studio::EmailDelivery.find_by!(email_key: "UserMailer#magic_link")
    args = ActiveJob::Arguments.deserialize(delivery.args)

    assert_equal [ @veyjin.email, "tok" ], args
    assert_includes UserMailer.public_send(delivery.action, *args).text_part.body.to_s, "Hi veyjin,"
  end
end
