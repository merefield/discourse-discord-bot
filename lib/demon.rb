# frozen_string_literal: true

require "demon/base"

module ::DiscordBot
  class Demon < ::Demon::Base
    RECONCILE_SECONDS = 10

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
        RECONCILE_SECONDS.times do
          break if stopping
          sleep 1
        end
      end
    ensure
      ::DiscordBot::Manager.deactivate! if owns_lease
      lease&.stop_renewal
      release_lease(lease) if owns_lease
    end

    def refresh_ownership(lease, owns_lease)
      acquired_lease = false

      if owns_lease
        return false unless lease.renewing?

        ::DiscordBot::Manager.reconcile!
        true
      elsif lease.acquire
        acquired_lease = true
        lease.start_renewal do |error = nil|
          log("Discord Bot: Gateway ownership renewal failed: #{error}", level: :error) if error
          ::DiscordBot::Manager.deactivate!
        end
        ::DiscordBot::Manager.activate!
        true
      else
        false
      end
    rescue StandardError => e
      if owns_lease || acquired_lease
        ::DiscordBot::Manager.deactivate!
        lease.stop_renewal
        release_lease(lease)
      end
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
