namespace :bot_tokens do
  # A computer player's remote runner token (BotToken, task tyrion-bot-api).
  # The token goes to stdout alone and is never shown again, so it can be
  # piped straight into the vault; everything else goes to stderr.
  #
  #   bin/rails "bot_tokens:issue[tyrion]"
  desc "Issue an API token for a computer player's remote runner (prints it once)"
  task :issue, [ :username ] => :environment do |_t, args|
    user = User.find_by(username: args[:username].to_s)
    abort "No player is called #{args[:username].inspect}." unless user
    abort "#{user.username} is not a computer player." unless user.computer?

    record, token = BotToken.issue!(user, name: ENV["NAME"])
    warn "Issued bot token #{record.id} for #{user.username}. Store it now; it is not shown again."
    puts token
  end

  desc "Revoke a bot token by id"
  task :revoke, [ :id ] => :environment do |_t, args|
    token = BotToken.find_by(id: args[:id])
    abort "No bot token #{args[:id].inspect}." unless token

    token.revoke!
    puts "Revoked bot token #{token.id} (#{token.user.username})."
  end

  desc "List bot tokens (ids, owners, last heard; never the tokens)"
  task list: :environment do
    BotToken.includes(:user).order(:id).each do |t|
      puts [ t.id, t.user.username, t.name, t.last_used_at&.iso8601 || "never used", t.revoked? ? "revoked" : "active" ].compact.join("  ")
    end
  end
end
