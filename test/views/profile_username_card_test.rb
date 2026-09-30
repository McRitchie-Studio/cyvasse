require "test_helper"

# [component] The profile's Username rows (task cyvasse-profile-username-edit):
# the edit page's card with its own form, drawn outside the engine's profile
# form, a refusal's name and reason, and a legacy name's suggestion; and the
# read page's row.
class ProfileUsernameCardTest < ActionView::TestCase
  def as(user)
    view.define_singleton_method(:current_user) { user }
  end

  def card(user)
    as(user)
    render partial: "profiles/username", locals: { user: }
  end

  def detached_form
    Nokogiri::HTML.fragment(view.content_for(:detached_forms).to_s)
  end

  test "the card shows the current username, with a Save for its own form" do
    card(User.new(id: 7, email: "rook@example.com", username: "the_rook"))

    assert_select "#username input#profile_username[name=username][value=the_rook][form=profile-username-form][maxlength='20'][required]"
    assert_select "#username button[type=submit][form=profile-username-form]", "Save"
    assert_select "form", 0, "no form inside the card: it sits inside the engine's profile form"
    assert_select "[data-legacy-username]", 0
    assert_select "[role=alert]", 0
  end

  test "its form is drawn in the layout's detached slot, and says it came from the profile" do
    card(User.new(id: 7, email: "rook@example.com", username: "the_rook"))

    form = detached_form.at_css("form#profile-username-form")
    assert form, "the detached form is rendered"
    assert_equal "/username", form["action"]
    assert_equal "patch", form.at_css("input[name=_method]")["value"]
    assert_equal "/profile/edit", form.at_css("input[name=return_to]")["value"]
    assert_equal "profile", form.at_css("input[name=from]")["value"]
  end

  test "a refusal shows the name tried and why" do
    flash[:username_attempt] = "jON"
    flash[:username_error] = "Username is taken."
    card(User.new(id: 7, email: "rook@example.com", username: "the_rook"))

    assert_select "input#profile_username[value=jON][aria-invalid=true][aria-describedby=profile_username_error]"
    assert_select "#profile_username_error[role=alert]", "Username is taken."
  end

  test "a legacy name that fails today's rules arrives with a suggestion" do
    card(User.new(id: 7, email: "rook@example.com", username: "the rook!", legacy_id: 11))

    assert_select "[data-legacy-username]", /the rook!/
    assert_select "input#profile_username[value=the_rook]"
  end

  test "the read page's row shows the name and the way to change it" do
    as(user = User.new(id: 7, email: "rook@example.com", username: "the_rook"))
    render partial: "profiles/username_summary", locals: { user: }

    assert_select "[data-username]", "the_rook"
    assert_select "a[href='/profile/edit#username']", "Change"
  end
end
