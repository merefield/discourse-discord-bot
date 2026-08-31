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

      def deactivate!
        @active = false
        stop_all
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

      def stop_all
        lifecycle_mutex.synchronize do
          active_runtimes =
            registry_mutex.synchronize do
              current_runtimes = runtimes.values
              runtimes.clear
              current_runtimes
            end

          active_runtimes.each { |runtime| stop_runtime(runtime) }
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

        [SiteSetting.discord_bot_token, SiteSetting.discord_bot_message_copy_ignore_bot_messages]
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

      def stop_runtime(runtime)
        return if runtime.nil?

        begin
          ::DiscordBot::Bot.stop(runtime.bot)
        rescue StandardError => e
          Rails.logger.error("Discord Bot: There was a problem stopping the bot: #{e}")
        ensure
          unless runtime.thread.join(STOP_TIMEOUT)
            Rails.logger.warn("Discord Bot: Timed out stopping the bot; terminating its thread")
            runtime.thread.kill
            runtime.thread.join
          end
        end
      end
    end
  end
end
