namespace :matches do
  desc "Close every online match whose seven-day move clock has run out (the player to move forfeits)"
  task expire: :environment do
    before = Match.finished.count
    Match.expire_stale!
    puts "Expired #{Match.finished.count - before} match(es)."
  end
end
