# The sign-in (magic link) email, Cyvasse's own. It shadows the engine's
# UserMailer (studio-engine app/mailers/user_mailer.rb) the way
# ApplicationMailer shadows the engine's: Zeitwerk resolves the constant to
# this file, so the engine's MagicLinksController, and ConfirmedSession, send
# this one.
#
# WHY CYVASSE OWNS IT (task trustworthy-sign-in-email). The engine's email
# landed in Gmail spam on 2026-09-30 with DKIM, SPF and DMARC all passing. The
# verdict was content: a "Welcome <name>!" hero over a stock beach GIF,
# "your sign-in link is below", "expires in 15 minutes" and a big button read
# like phishing. This one is text-led: a short greeting, why it came, one
# modest button with the plain link under it, and a footer with the site name.
# No images at all, so no image host to earn a reputation.
#
# It does not read the engine's /admin/emails settings (banner, subject, body,
# button) for the sign-in email: those fields describe the branded design this
# replaces. Copy changes are made here.
#
# Every URL is built on the email link host (ApplicationMailer, and
# Cyvasse.email_link_host), never the canonical host.
class UserMailer < ApplicationMailer
  include Studio::MagicLinkIssuing

  # Never used as a greeting: an account named for its role reads as an
  # automated or phishing message ("Welcome admin!"), whatever the account is.
  UNGREETABLE = %w[admin administrator root user viewer member guest staff support].freeze

  # `email` is a raw string: the recipient may not have an account yet.
  def magic_link(email, token)
    @app_name = Studio.app_name
    @magic_url = magic_link_url_for(token)
    @site_host = URI.parse(@magic_url).host
    @greeting_name = greeting_name(email)
    mail(to: email, subject: "Your #{@app_name} sign-in link")
  end

  private

  # The player's username when they have a real one, else nil (the greeting
  # then names no one). Never a guest's "Guest_4821", a computer player, or a
  # role word. A failed lookup must never be the reason a sign-in email fails.
  def greeting_name(email)
    user = User.find_by(email: email.to_s.strip.downcase)
    return if user.nil? || user.guest? || user.computer?

    name = user.username.to_s.strip
    name if name.present? && UNGREETABLE.exclude?(name.downcase) && name.casecmp(user.role.to_s).nonzero?
  rescue StandardError
    nil
  end
end
