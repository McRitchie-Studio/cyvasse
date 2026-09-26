namespace :users do
  # The release post-deploy command (devops.post_deploy_cmd). Narrow on
  # purpose: it seeds only User::SEED_IDENTITIES, idempotently, so production
  # lands the same admins and member as a desk without running db/seeds.rb.
  desc "Create any missing seed identity (two admins, one member); never overwrites"
  task seed_identities: :environment do
    User.seed_identities!.each { |user| puts "Seeded #{user.role}: #{user.email}" }
  end
end
