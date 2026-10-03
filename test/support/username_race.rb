# Lose the username race (task cyvasse-username-unique-index): for the block,
# User#username_free_in_any_case passes every name, as it does for two saves
# that both check before either writes. Only the unique indexes can then stop
# a second account taking a name in another case.
module UsernameRace
  def as_if_the_check_raced
    original = User.instance_method(:username_free_in_any_case)
    User.define_method(:username_free_in_any_case) { nil }
    yield
  ensure
    User.define_method(:username_free_in_any_case, original)
    User.send(:private, :username_free_in_any_case)
  end
end
