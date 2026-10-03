class LegalController < ApplicationController
  # /privacy and /terms are PUBLIC: a policy a visitor must sign in to read is
  # no policy at all, and the site footer links both from every public page.
  # They render static copy and read no app data. Allowlisted in
  # test/integration/auth_gate_test.rb; "legal" is also in
  # Studio.site_footer_controllers, so a signed-in player keeps the footer here.
  #
  # THE COPY DESCRIBES WHAT THIS APP DOES. A change to sign-in, what a player's
  # account or games store, chat, email, file storage, cookies or anything else
  # a player's data touches owes an edit to app/views/legal/privacy.html.erb in
  # the same change; the README's "Legal pages" table names the file each
  # statement rests on.
  skip_before_action :require_authentication

  def privacy
  end

  def terms
  end
end
