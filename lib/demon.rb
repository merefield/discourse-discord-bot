# frozen_string_literal: true

require "demon/base"

module ::DiscordBot
  class Demon < ::Demon::Base
    RECONCILE_SECONDS = 10

    class << self
      def prefix
        "discord_bot"
      end

      def start(count = 1, verbose: false, logger: nil)
        @start_options = { count: count, verbose: verbose, logger: logger }
        super if required?
      end

      def ensure_running
        unless required?
          stop
          return
        end

        if demons.blank?
          options = @start_options || { count: 1, verbose: false, logger: nil }
          start(options[:count], verbose: options[:verbose], logger: options[:logger])
        else
          demons.each_value { |demon| demon.start unless demon.started }
          super
        end
      end

      def required?
        required = false
        RailsMultisite::ConnectionManagement.each_connection do
          required ||= SiteSetting.discord_bot_enabled && SiteSetting.discord_bot_token.present?
        end
        required
      rescue StandardError => error
        Rails.logger.warn(
          "Discord Bot: Could not determine whether the gateway demon is needed: #{error}",
        )
        true
      end
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
        unless lease.renewing?
          ::DiscordBot::Manager.deactivate!(graceful: false)
          return false
        end

        ::DiscordBot::Manager.reconcile!
        true
      elsif lease.acquire
        acquired_lease = true
        lease.start_renewal do |error = nil|
          log("Discord Bot: Gateway ownership renewal failed: #{error}", level: :error) if error
          ::DiscordBot::Manager.deactivate!(graceful: false)
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
