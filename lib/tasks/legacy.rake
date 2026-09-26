namespace :legacy do
  # Epic cyvasse-revival pieces 10a and 10b. Point it at the CSV export of the
  # old cyvasse-game database (README, "Legacy import"); it prints counts only.
  # users.csv and matches.csv are required; messages.csv and setups.csv are
  # imported when the folder holds them. Idempotent: a rerun imports nothing
  # it already has.
  #
  #   LEGACY_CSV_DIR=~/Backups/heroku-personal-2026-09-25/csv bin/rails legacy:import
  desc "Import the old Cyvasse players, matches, messages and lineups from the CSVs in LEGACY_CSV_DIR"
  task import: :environment do
    dir = ENV["LEGACY_CSV_DIR"].to_s
    abort "Set LEGACY_CSV_DIR to the folder holding users.csv and matches.csv." if dir.empty?

    path = ->(name) { File.join(File.expand_path(dir), name) }
    [ "users.csv", "matches.csv" ].each { |name| abort "Missing #{path.(name)}." unless File.file?(path.(name)) }
    optional = ->(name) { File.file?(path.(name)) ? path.(name) : nil }

    report = LegacyImport.new(users_csv: path.("users.csv"), matches_csv: path.("matches.csv"),
                              messages_csv: optional.("messages.csv"), setups_csv: optional.("setups.csv")).run
    puts report.lines
  end
end
