# Cyvasse seeds — idempotent bootstrap (`bin/rails db:seed`). Creates anything
# missing and never overwrites existing rows. The list lives on the model:
# User::SEED_IDENTITIES.
User.seed_identities!.each { |user| puts "Seeded #{user.role}: #{user.email}" }
