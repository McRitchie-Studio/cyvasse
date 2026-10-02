# frozen_string_literal: true

module Cyvasse
  # How many database connections one web process may hold, and the two
  # thread pools that draw on them. Read by config/database.yml (the pool,
  # `max_connections`), config/puma.rb (the request threads) and
  # config/application.rb (ActionCable's worker pool), so the three cannot
  # drift apart.
  #
  # A pool smaller than the threads that check connections out of it makes a
  # busy thread wait checkout_timeout (5s) and then raise
  # ActiveRecord::ConnectionTimeoutError. Before this, production's pool was
  # 5 while Puma ran 3 request threads and ActionCable ran 4 workers (live
  # chat): 7 threads on 5 connections.
  #
  # The pool is threads + cable workers + 1. The one spare covers the
  # ActiveJob async adapter, which runs the engine's email deliveries on
  # threads inside the same process.
  #
  # Heroku Postgres essential-0 allows 20 connections in all. One web dyno at
  # the defaults holds at most 8; a restart briefly overlaps two (16), and a
  # release-phase migrate or a one-off console takes one or two more. Raise
  # RAILS_MAX_THREADS or CABLE_WORKER_POOL_SIZE, or add a dyno, only with that
  # sum in view.
  module ConnectionBudget
    DEFAULT_THREADS = 3
    DEFAULT_CABLE_WORKERS = 4
    SPARE = 1

    module_function

    def threads(env = ENV)
      positive(env, "RAILS_MAX_THREADS", DEFAULT_THREADS)
    end

    def cable_workers(env = ENV)
      positive(env, "CABLE_WORKER_POOL_SIZE", DEFAULT_CABLE_WORKERS)
    end

    def pool(env = ENV)
      threads(env) + cable_workers(env) + SPARE
    end

    # A blank, zero, negative or non-numeric value falls back to the default
    # rather than sizing a pool of zero.
    def positive(env, name, default)
      value = Integer(env.fetch(name, "").to_s.strip, exception: false)
      value&.positive? ? value : default
    end
    private_class_method :positive
  end
end
