# frozen_string_literal: true

module ::DiscordBot
  class Lease
    KEY = "discord_bot:gateway_owner"
    TTL = 30

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

    def initialize(redis: Discourse.redis.without_namespace, key: KEY, token: SecureRandom.hex(16))
      @redis = redis
      @key = key
      @token = token
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
  end
end
