# frozen_string_literal: true

require "demon/base"

module ::DiscordBot
  class Demon < ::Demon::Base
    LEASE_REFRESH_SECONDS = 10

    def self.prefix
      "discord_bot"
    end

    private

    def after_fork
      stopping = false
      Signal.trap("TERM") { stopping = true }
      lease = ::DiscordBot::Lease.new
      owns_lease = false

      until stopping
        owns_lease = refresh_ownership(lease, owns_lease)
        LEASE_REFRESH_SECONDS.times do
          break if stopping
          sleep 1
        end
      end
    ensure
      ::DiscordBot::Manager.deactivate! if owns_lease
      release_lease(lease) if owns_lease
    end

    def refresh_ownership(lease, owns_lease)
      if owns_lease
        unless lease.renew
          ::DiscordBot::Manager.deactivate!
          return false
        end

        ::DiscordBot::Manager.reconcile!
        true
      elsif lease.acquire
        ::DiscordBot::Manager.activate!
        true
      else
        false
      end
    rescue StandardError => e
      ::DiscordBot::Manager.deactivate! if owns_lease
      log("Discord Bot: Gateway ownership check failed: #{e}", level: :error)
      false
    end

    def release_lease(lease)
      lease.release
    rescue StandardError => e
      log("Discord Bot: Gateway ownership release failed: #{e}", level: :error)
    end
  end
end
