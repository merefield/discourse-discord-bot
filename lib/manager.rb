# frozen_string_literal: true

module ::DiscordBot
  # Owns the active Discord bot and thread for each multisite database.
  class Manager
    Runtime = Struct.new(:bot, :thread, keyword_init: true)

    class << self
      def bot_for(db)
        registry_mutex.synchronize { runtimes[db]&.bot }
      end

      def restart(db)
        lifecycle_mutex.synchronize do
          stop_runtime(delete_runtime(db))
          start_runtime(db) if should_start?
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
        Discourse.running_in_rack? && SiteSetting.discord_bot_enabled &&
          SiteSetting.discord_bot_token.present?
      end

      def start_runtime(db)
        bot = ::DiscordBot::Bot.init
        thread = Thread.new { run_bot(db, bot) }

        registry_mutex.synchronize { runtimes[db] = Runtime.new(bot: bot, thread: thread) }
      end

      def run_bot(db, bot)
        RailsMultisite::ConnectionManagement.establish_connection(db: db)
        bot.run
      rescue StandardError => e
        Rails.logger.error("Discord Bot: There was a problem: #{e}")
      end

      def stop_runtime(runtime)
        return if runtime.nil?

        begin
          runtime.bot.stop
        rescue StandardError => e
          Rails.logger.error("Discord Bot: There was a problem stopping the bot: #{e}")
        ensure
          runtime.thread.join
        end
      end
    end
  end
end
