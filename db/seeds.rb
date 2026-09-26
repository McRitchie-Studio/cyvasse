# Cyvasse seeds — idempotent bootstrap (`bin/rails db:seed`). Creates anything
# missing and never overwrites existing rows. The list lives on the model:
# User::SEED_IDENTITIES.
User.seed_identities!.each { |user| puts "Seeded #{user.role}: #{user.email}" }

# Made-up players and conversations for the inbox and the admin
# Conversations page, on a developer machine only (lib/demo_conversations.rb).
puts "Seeded #{DemoConversations.seed!} demo message(s)." if Rails.env.development?
