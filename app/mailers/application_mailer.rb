class ApplicationMailer < ActionMailer::Base
  # The sender configured in config/initializers/studio.rb (Studio.mailer_from,
  # resolved per transport). This class shadows the engine's ApplicationMailer,
  # so the engine's UserMailer (the magic link) inherits this default too; the
  # scaffold's "from@example.com" placeholder would have been sent as is.
  default from: -> { Studio.mailer_from || ENV["MAILER_FROM"] || "Cyvasse <team@mcritchie.studio>" }
  layout "mailer"

  # Links in mail go to the email link host (Cyvasse.email_link_host), never
  # the canonical host: an established domain, not a new one, is what keeps a
  # sign-in link out of spam, and the redirect carries the click on to the
  # canonical host (lib/cyvasse/canonical_host.rb). Read when the mail is
  # built. Where none is set (a desk, a test) the environment's own options
  # stand. Every mailer inherits this, the magic link included (UserMailer).
  def default_url_options
    Cyvasse::CanonicalHost.email_url_options || super
  end
end
