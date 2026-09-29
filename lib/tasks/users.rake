namespace :users do
  # The release post-deploy command (devops.post_deploy_cmd). Narrow on
  # purpose: it seeds only User::SEED_IDENTITIES, idempotently, so production
  # lands the same admins and member as a desk without running db/seeds.rb.
  desc "Create any missing seed identity (two admins, one member); never overwrites"
  task seed_identities: :environment do
    User.seed_identities!.each { |user| puts "Seeded #{user.role}: #{user.email}" }
  end

  # The post-deploy command of task cyvasse-bot-portraits. Narrow on purpose:
  # it touches only the six named computer players, creating any that are
  # missing and setting each one's portrait (users.portrait) in place.
  desc "Create any missing named computer player and set its portrait; safe to re-run"
  task seed_computer_players: :environment do
    User.seed_computer_players!.each { |user| puts "Seeded computer: #{user.username} (#{user.portrait || "piece art"})" }
  end
end
