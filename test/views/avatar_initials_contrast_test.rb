require "test_helper"

# [component] White avatar initials meet WCAG AA on every avatar colour (task
# cyvasse-avatar-initial-contrast). The engine's components/avatar draws
# text-white initials on User#avatar_color, so every palette entry must reach
# 4.5:1 against white, and a rendered initials avatar must carry one of them.
class AvatarInitialsContrastTest < ActionView::TestCase
  AA_NORMAL_TEXT = 4.5

  # WCAG 2.x relative luminance of a #RRGGBB colour.
  def relative_luminance(hex)
    r, g, b = hex.delete_prefix("#").scan(/../).map do |pair|
      c = pair.hex / 255.0
      c <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055)**2.4
    end
    (0.2126 * r) + (0.7152 * g) + (0.0722 * b)
  end

  def contrast_with_white(hex)
    (1.0 + 0.05) / (relative_luminance(hex) + 0.05)
  end

  test "the luminance formula matches known WCAG anchors" do
    assert_in_delta 21.0, contrast_with_white("#000000"), 0.01
    assert_in_delta 1.0, contrast_with_white("#FFFFFF"), 0.01
    # The old pink, reported at 3.53:1 by the contrast audit.
    assert_in_delta 3.53, contrast_with_white("#EC4899"), 0.01
  end

  test "every avatar colour gives white initials at least 4.5:1" do
    assert_equal 8, User::AVATAR_COLORS.size, "the count fixes each player's colour index"
    User::AVATAR_COLORS.each do |hex|
      assert_match(/\A#\h{6}\z/, hex)
      ratio = contrast_with_white(hex)
      assert_operator ratio, :>=, AA_NORMAL_TEXT, "#{hex} gives white initials only #{ratio.round(2)}:1"
    end
  end

  test "the palette stays varied: eight distinct colours" do
    assert_equal User::AVATAR_COLORS.size, User::AVATAR_COLORS.map(&:upcase).uniq.size
  end

  test "an initials avatar renders white text on a passing colour" do
    user = User.create!(email: "carl@example.com", name: "Carl Test")
    render partial: "components/avatar", locals: { user: user, size: "nav" }

    assert_select "div.text-white", text: "C" do |divs|
      style = divs.first["style"]
      hex = style[/background-color:\s*(#\h{6})/, 1]
      assert_equal user.avatar_color, hex
      assert_operator contrast_with_white(hex), :>=, AA_NORMAL_TEXT
    end
  end
end
