# Cyvasse seeds — idempotent bootstrap (`bin/rails db:seed`). Creates anything
# missing; the only field it overwrites is a computer player's portrait. The
# lists live on the model: User::SEED_IDENTITIES and User::COMPUTER_PORTRAITS.
User.seed_identities!.each { |user| puts "Seeded #{user.role}: #{user.email}" }

# The six named computer players and their portraits (User::COMPUTER_PORTRAITS,
# app/assets/images/bots). Unlike the identities, a re-run updates an existing
# computer player's portrait in place.
User.seed_computer_players!.each { |user| puts "Seeded computer: #{user.username} (#{user.portrait})" }

# Made-up players and conversations for the inbox and the admin
# Conversations page, on a developer machine only (lib/demo_conversations.rb).
puts "Seeded #{DemoConversations.seed!} demo message(s)." if Rails.env.development?
