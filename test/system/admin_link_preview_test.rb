require "application_system_test_case"

# [e2e] An admin opens Link preview from Cyvasse's admin menu, sees the card a
# shared link unfurls into (the drafted copy until someone saves), edits the
# description, and the live card shows it and the saved row holds it (task
# cyvasse-adopts-link-preview; studio-engine docs/LINK_PREVIEW.md). What a
# shared link then unfurls into is test/integration/link_preview_test.rb.
class AdminLinkPreviewSystemTest < ApplicationSystemTestCase
  setup do
    @admin = User.create!(email: "admin@example.com", name: "Admin", role: "admin", username: "boss")
  end

  teardown { Studio::SiteIdentity.bust_cache! }

  test "an admin edits the site card from the admin menu" do
    visit link_path(token: Studio::Link.create_magic_link(email: @admin.email).token)
    assert_text "Signed in as #{@admin.player_name}"

    find("button[aria-label='Toggle admin menu']", match: :first).click
    click_on "Link preview"

    assert_selector "h1", text: "Link Preview"
    assert_selector "[data-link-preview-card-title]", text: Studio.site_title
    assert_selector "[data-link-preview-card-description]", text: Studio.site_description

    fill_in "Description", with: "Cyvasse, the hex-board game from the books, free online."
    assert_selector "[data-link-preview-card-description]", text: "Cyvasse, the hex-board game from the books, free online."
    click_on "Save"

    assert_selector "[data-link-preview-card-description]", text: "Cyvasse, the hex-board game from the books, free online."
    assert_equal "Cyvasse, the hex-board game from the books, free online.", Studio::SiteIdentity.current.description
  end
end
