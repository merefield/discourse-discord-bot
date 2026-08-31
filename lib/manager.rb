# frozen_string_literal: true

module ::DiscordBot
  # Owns the active Discord bot and thread for each multisite database.
  class Manager
    STOP_TIMEOUT = 5

    Runtime = Struct.new(:bot, :thread, :configuration, keyword_init: true)

    class << self
      def activate!
        @active = true
        reconcile!
      end

      def deactivate!(graceful: true)
        @active = false
        stop_all(graceful: graceful)
      end

      def bot_for(db)
        registry_mutex.synchronize { runtimes[db]&.bot }
      end

      def with_bot_connection(bot)
        db =
          registry_mutex.synchronize do
            runtimes.find { |_database, runtime| runtime.bot.equal?(bot) }&.first
          end
        return if db.nil?

        RailsMultisite::ConnectionManagement.with_connection(db) { yield db }
      end

      def reconcile!
        return unless @active

        RailsMultisite::ConnectionManagement.each_connection do |db|
          needs_restart =
            RailsMultisite::ConnectionManagement.with_connection(db) do
              active_configuration = registry_mutex.synchronize { runtimes[db]&.configuration }
              active_configuration != desired_configuration
            end

          restart(db) if needs_restart
        end
      end

      def restart(db)
        return unless @active

        RailsMultisite::ConnectionManagement.with_connection(db) do
          lifecycle_mutex.synchronize do
            stop_runtime(delete_runtime(db))
            start_runtime(db) if should_start?
          end
        end
      end

      def stop_all(graceful: true)
        lifecycle_mutex.synchronize do
          active_runtimes =
            registry_mutex.synchronize do
              current_runtimes = runtimes.values
              runtimes.clear
              current_runtimes
            end

          active_runtimes.each { |runtime| stop_runtime(runtime, graceful: graceful) }
        end
      end

      private

      def delete_runtime(db)
        registry_mutex.synchronize { runtimes.delete(db) }
      end

      def lifecycle_mutex
        @lifecycle_mutex ||= Mutex.new
      end

      def registry_mutex
        @registry_mutex ||= Mutex.new
      end

      def runtimes
        @runtimes ||= {}
      end

      def should_start?
        SiteSetting.discord_bot_enabled && SiteSetting.discord_bot_token.present?
      end

      def desired_configuration
        return unless should_start?

        [
          SiteSetting.discord_bot_token,
          SiteSetting.discord_bot_message_copy_ignore_bot_messages,
          SiteSetting.discord_bot_admin_role_id,
        ]
      end

      def start_runtime(db)
        configuration = desired_configuration
        return if configuration.nil?

        bot = ::DiscordBot::Bot.init
        runtime = Runtime.new(bot: bot, configuration: configuration)
        registered = Queue.new
        thread =
          Thread.new do
            registered.pop
            run_bot(db, runtime)
          end
        runtime.thread = thread

        registry_mutex.synchronize { runtimes[db] = runtime }
        registered << true
        runtime
      end

      def run_bot(db, runtime)
        RailsMultisite::ConnectionManagement.establish_connection(db: db)
        runtime.bot.run
      rescue StandardError => e
        Rails.logger.error("Discord Bot: There was a problem: #{e}")
      ensure
        registry_mutex.synchronize { runtimes.delete(db) if runtimes[db].equal?(runtime) }
      end

      def stop_runtime(runtime, graceful: true)
        return if runtime.nil?

        clean_shutdown = true
        begin
          ::DiscordBot::Bot.stop(runtime.bot)
        rescue StandardError => e
          clean_shutdown = false
          Rails.logger.error("Discord Bot: There was a problem stopping the bot: #{e}")
        end

        clean_shutdown &&= wait_for_runtime(runtime, graceful ? STOP_TIMEOUT : 0)
        return if clean_shutdown

        Rails.logger.warn("Discord Bot: Forcing remaining gateway and event threads to stop")
        event_threads = ::DiscordBot::Bot.event_threads(runtime.bot)
        ::DiscordBot::Bot.force_stop(runtime.bot)
        event_threads.concat(::DiscordBot::Bot.event_threads(runtime.bot)).uniq.each(&:kill)
        event_threads.each(&:join)
        runtime.thread.kill if runtime.thread.alive?
        runtime.thread.join
      end

      def wait_for_runtime(runtime, timeout)
        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout

        loop do
          threads = active_runtime_threads(runtime)
          return true if threads.empty?

          remaining = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
          return false unless remaining.positive?

          threads.first.join([remaining, 0.05].min)
        end
      end

      def active_runtime_threads(runtime)
        [runtime.thread, *::DiscordBot::Bot.event_threads(runtime.bot)].compact.uniq.select(
          &:alive?
        )
      end
    end
  end
end
