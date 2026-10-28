require "test_helper"

# [unit] The studio-engine floor, with the reason attached, so a lockfile that
# drifts below what this app relies on fails here rather than in production.
# The migration half of the contract is test/lib/engine_migrations_installed_test.rb.
#
#   0.115.1 — the floor before this file existed (see the Gemfile note).
#   0.116.0 — the navbar account group: the account opens the link sidebar,
#             as the gear does, so the engine lights the gear, the name and the
#             avatar together on hover, the avatar with a primary glow. Nothing
#             raises below it; the three hover apart.
class EnginePinContractTest < ActiveSupport::TestCase
  MINIMUM = Gem::Version.new("0.116.0")

  test "the resolved studio-engine is at or above the floor this app depends on" do
    assert_operator Gem::Version.new(Studio::VERSION), :>=, MINIMUM,
                    "studio-engine #{Studio::VERSION} is below #{MINIMUM}: the navbar account group needs it"
  end

  # The 0.116.0 floor is SILENT, so a version number alone cannot show the feature
  # arrived: this asks the resolved engine for the link-sidebar account group rule,
  # and this app for the sidebar sections that make the account open the link
  # sidebar. Either missing and the gear, name and avatar hover apart, nothing raised.
  test "the resolved engine lights this navbar's gear, name and avatar as one group" do
    css = Studio::Engine.root.join("app/assets/tailwind/studio_engine/engine.css").read

    assert_includes css, ":has(> [data-nav-tools]):has(> [data-nav-account][aria-controls~=\"studio-link-sidebar\"])",
                    "studio-engine #{Studio::VERSION} has no link-sidebar account group rule"
    assert Studio.sidebar_sections.present?,
           "the account opens the link sidebar only when config.sidebar_sections is set"
  end
end
