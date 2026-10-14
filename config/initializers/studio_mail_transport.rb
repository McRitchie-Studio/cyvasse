require "studio/mail_transport"

# Resend when RESEND_API_KEY is present, local capture on a developer desk
# (studio-engine docs/EMAIL_TRANSPORT.md). The engine dropped SES in 0.102.0.
Studio::MailTransport.configure!
