# Sets the host environment variables lib/cyvasse/canonical_host.rb reads
# (CANONICAL_HOST, EMAIL_LINK_HOST) for one block, and puts back exactly what
# was there, unset included. Both hosts are read per mail and per request, so
# no reload is needed.
module MailHosts
  HOST_VARS = %w[CANONICAL_HOST EMAIL_LINK_HOST].freeze

  def with_hosts(canonical: nil, email: nil)
    previous = HOST_VARS.index_with { |name| ENV[name] }
    ENV["CANONICAL_HOST"] = canonical
    ENV["EMAIL_LINK_HOST"] = email
    yield
  ensure
    previous.each { |name, value| ENV[name] = value }
  end

  # Every host an absolute URL in `body` names, links and any image alike.
  def hosts_in(body)
    body.to_s.scan(%r{https?://([^/"'\s<>]+)}).flatten.uniq
  end
end
