namespace :legacy do
  # Epic cyvasse-revival piece 10a. Point it at the CSV export of the old
  # cyvasse-game database (README, "Legacy import"); it prints counts only.
  # Idempotent: a rerun imports nothing it already has.
  #
  #   LEGACY_CSV_DIR=~/Backups/heroku-personal-2026-09-25/csv bin/rails legacy:import
  desc "Import the old Cyvasse players and matches from users.csv and matches.csv in LEGACY_CSV_DIR"
  task import: :environment do
    dir = ENV["LEGACY_CSV_DIR"].to_s
    abort "Set LEGACY_CSV_DIR to the folder holding users.csv and matches.csv." if dir.empty?

    users_csv = File.join(File.expand_path(dir), "users.csv")
    matches_csv = File.join(File.expand_path(dir), "matches.csv")
    [ users_csv, matches_csv ].each { |path| abort "Missing #{path}." unless File.file?(path) }

    report = LegacyImport.new(users_csv: users_csv, matches_csv: matches_csv).run
    puts report.lines
  end
end
