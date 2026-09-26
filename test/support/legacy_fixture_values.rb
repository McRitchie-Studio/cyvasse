# Every value in the synthetic legacy CSVs (test/fixtures/files/legacy/) that
# an import error must never print: each cell of four characters or more that
# is not a bare number (legacy ids may be named). Emails, usernames, message
# text, lineup names, army strings and timestamps all qualify.
module LegacyFixtureValues
  DIR = Rails.root.join("test/fixtures/files/legacy")

  def self.all
    @all ||= Dir[DIR.join("*.csv")].flat_map do |path|
      CSV.read(path, headers: true).flat_map { |row| row.fields.compact }
    end.map(&:strip).uniq.select { |value| value.length >= 4 && !value.match?(/\A\d+\z/) }
  end

  # Fails naming the first fixture value `text` carries.
  def refute_legacy_values(text, what = "the error")
    assert_operator LegacyFixtureValues.all.size, :>, 40, "the fixture list must hold the CSVs' values"
    leaked = LegacyFixtureValues.all.select { |value| text.downcase.include?(value.downcase) }
    assert_empty leaked, "#{what} must carry no row value"
  end
end
