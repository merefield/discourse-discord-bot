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
        if required?
          super
        else
          ::DiscordBot::LifecycleLogger.verbose_for_any_site(
            "Gateway supervisor not spawned because no configured site requires it",
            logger: logger || Rails.logger,
          )
        end
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

    def run
      super
      log(
        "Discord Bot: Spawned gateway supervisor process pid=#{pid} host=#{Socket.gethostname}",
        level: :warn,
      )
    end

    def ensure_running
      previous_pid = pid
      super
      return if previous_pid.nil? || previous_pid == pid

      log(
        "Discord Bot: Replaced stopped gateway supervisor process pid=#{previous_pid} with pid=#{pid}",
        level: :warn,
      )
    end

    def stop
      stopping_pid = pid
      return super if stopping_pid.nil?

      log("Discord Bot: Stopping gateway supervisor process pid=#{stopping_pid}", level: :warn)
      super
      log("Discord Bot: Stopped gateway supervisor process pid=#{stopping_pid}", level: :warn)
    end

    private

    def after_fork
      stopping = false
      Signal.trap("TERM") { stopping = true }
      lease = ::DiscordBot::Lease.new
      owns_lease = false
      verbose_log(
        "Gateway supervisor process is ready pid=#{Process.pid} host=#{Socket.gethostname}",
      )

      until stopping
        owns_lease = refresh_ownership(lease, owns_lease)
        RECONCILE_SECONDS.times do
          break if stopping
          sleep 1
        end
      end
    rescue StandardError => error
      log(
        "Discord Bot: Gateway supervisor process failed: #{error.class}: #{error.message}",
        level: :error,
      )
      raise
    ensure
      ::DiscordBot::Manager.deactivate! if owns_lease
      lease&.stop_renewal
      release_lease(lease) if owns_lease
    end

    def refresh_ownership(lease, owns_lease)
      acquired_lease = false

      if owns_lease
        unless lease.renewing?
          unless @lease_loss_logged
            log("Discord Bot: Gateway ownership lost; force stopping runtimes", level: :warn)
          end
          @lease_loss_logged = true
          ::DiscordBot::Manager.deactivate!(graceful: false)
          return false
        end

        ::DiscordBot::Manager.reconcile!
        true
      elsif lease.acquire
        acquired_lease = true
        @standby_logged = false
        @lease_loss_logged = false
        verbose_log("Acquired cluster gateway lease")
        lease.start_renewal do |error = nil|
          if error
            log(
              "Discord Bot: Gateway ownership renewal failed: #{error.class}: #{error.message}",
              level: :error,
            )
          else
            log("Discord Bot: Gateway ownership lost; force stopping runtimes", level: :warn)
          end
          @lease_loss_logged = true
          ::DiscordBot::Manager.deactivate!(graceful: false)
        end
        ::DiscordBot::Manager.activate!
        true
      else
        unless @standby_logged
          verbose_log("Gateway supervisor is standing by because another process owns the lease")
          @standby_logged = true
        end
        false
      end
    rescue StandardError => e
      if owns_lease || acquired_lease
        ::DiscordBot::Manager.deactivate!
        lease.stop_renewal
        release_lease(lease)
      end
      log("Discord Bot: Gateway ownership check failed: #{e.class}: #{e.message}", level: :error)
      false
    end

    def release_lease(lease)
      if lease.release
        verbose_log("Released cluster gateway lease")
      else
        log("Discord Bot: Gateway lease was no longer owned during release", level: :warn)
      end
    rescue StandardError => e
      log("Discord Bot: Gateway ownership release failed: #{e.class}: #{e.message}", level: :error)
    end

    def verbose_log(message)
      return false unless ::DiscordBot::LifecycleLogger.enabled_for_any_site?

      log("Discord Bot: #{message}", level: :warn)
      true
    end
  end
end
