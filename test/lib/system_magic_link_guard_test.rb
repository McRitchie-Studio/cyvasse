require "test_helper"

# [unit] System specs follow a magic link only through visit_magic_link
# (test/application_system_test_case.rb), which waits on the URL leaving /l/.
# A bare `visit link_path(...)` followed by assert_text can hold the confirm
# interstitial's <html> as the next document replaces it, and chromedriver
# errors (task cyvasse-board-visit-polish).
class SystemMagicLinkGuardTest < ActiveSupport::TestCase
  test "no system spec visits a magic link without visit_magic_link" do
    offenders = Dir[Rails.root.join("test/system/**/*.rb")].flat_map do |path|
      File.readlines(path).each_with_index.filter_map do |line, index|
        "#{Pathname(path).relative_path_from(Rails.root)}:#{index + 1}" if line.match?(/\bvisit\s*\(?\s*link_path\b/)
      end
    end

    assert_empty offenders, "use visit_magic_link(token) instead"
  end
end
