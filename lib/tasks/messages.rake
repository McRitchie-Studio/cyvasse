namespace :messages do
  desc "Seed synthetic players, matches and conversations for a local demo (never in production)"
  task demo: :environment do
    puts "Created #{DemoConversations.seed!} demo message(s)."
  end
end
