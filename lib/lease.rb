# frozen_string_literal: true

module ::DiscordBot
  class Lease
    KEY = "discord_bot:gateway_owner"
    TTL = 30
    REFRESH_SECONDS = TTL / 3

    RENEW_SCRIPT = DiscourseRedis::EvalHelper.new <<~LUA
        if redis.call("GET", KEYS[1]) == ARGV[1] then
          return redis.call("EXPIRE", KEYS[1], ARGV[2])
        end

        return 0
      LUA

    RELEASE_SCRIPT = DiscourseRedis::EvalHelper.new <<~LUA
        if redis.call("GET", KEYS[1]) == ARGV[1] then
          return redis.call("DEL", KEYS[1])
        end

        return 0
      LUA

    def initialize(
      redis: Discourse.redis,
      key: KEY,
      token: SecureRandom.hex(16),
      refresh_seconds: REFRESH_SECONDS
    )
      @redis = redis.respond_to?(:without_namespace) ? redis.without_namespace : redis
      @key = redis.respond_to?(:namespace_key) ? redis.namespace_key(key) : key
      @token = token
      @refresh_seconds = refresh_seconds
    end

    def acquire
      !!@redis.set(@key, @token, nx: true, ex: TTL)
    end

    def renew
      RENEW_SCRIPT.eval(@redis, [@key], [@token, TTL]).to_i == 1
    end

    def release
      RELEASE_SCRIPT.eval(@redis, [@key], [@token]).to_i == 1
    end

    def start_renewal(&on_lost)
      return if renewing?

      @renewal_thread =
        Thread.new do
          loop do
            sleep @refresh_seconds
            begin
              next if renew
            rescue StandardError => error
              on_lost.call(error)
              break
            end

            on_lost.call
            break
          end
        end
    end

    def renewing?
      @renewal_thread&.alive? || false
    end

    def stop_renewal
      @renewal_thread&.kill
      @renewal_thread&.join
      @renewal_thread = nil
    end
  end
end
