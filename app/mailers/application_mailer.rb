class ApplicationMailer < ActionMailer::Base
  # The sender configured in config/initializers/studio.rb (Studio.mailer_from,
  # resolved per transport). This class shadows the engine's ApplicationMailer,
  # so the engine's UserMailer (the magic link) inherits this default too; the
  # scaffold's "from@example.com" placeholder would have been sent as is.
  default from: -> { Studio.mailer_from || ENV["MAILER_FROM"] || "Cyvasse <team@mcritchie.studio>" }
  layout "mailer"

  # Links in mail go to the canonical host (Cyvasse.canonical_host), read when
  # the mail is built so it can never drift from the redirect that enforces it.
  # Where none is set (a desk, a test) the environment's own options stand.
  def default_url_options
    Cyvasse::CanonicalHost.url_options || super
  end
end
