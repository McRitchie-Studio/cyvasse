require "studio/mail_transport"

# SES when MAIL_TRANSPORT=ses and its SMTP credentials are present, Resend as
# the rollback, local capture on a developer desk (studio-engine
# docs/EMAIL_TRANSPORT.md).
Studio::MailTransport.configure!
