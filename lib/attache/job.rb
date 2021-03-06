class Attache::Job
  RETRY_DURATION = ENV.fetch('CACHE_EVICTION_INTERVAL_SECONDS') { 60 }.to_i / 3

  def perform(method, env, args)
    config = Attache::VHost.new(env)
    config.send(method, args.symbolize_keys)
  rescue Exception
    Attache.logger.error $@
    Attache.logger.error $!
    Attache.logger.error [method, args].inspect
    self.class.perform_in(RETRY_DURATION, method, env, args)
  end

  # Background processing setup

  if defined?(::SuckerPunch::Job)
    include ::SuckerPunch::Job
    def later(sec, *args)
      after(sec) { perform(*args) }
    end
    def self.perform_async(*args)
      self.new.async.perform(*args)
    end
    def self.perform_in(duration, *args)
      self.new.async.later(duration, *args)
    end
  else
    include Sidekiq::Worker
    sidekiq_options :queue => :attache_vhost_jobs
    sidekiq_retry_in {|count| RETRY_DURATION} # uncaught exception, retry after RETRY_DURATION
  end
end
