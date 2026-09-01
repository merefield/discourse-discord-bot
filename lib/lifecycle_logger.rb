# frozen_string_literal: true

module ::DiscordBot
  class LifecycleLogger
    class << self
      def verbose(message, db: nil, logger: Rails.logger)
        return false unless enabled?(db: db)

        logger.warn(format_message(message, db: db))
        true
      end

      def verbose_for_any_site(message, logger: Rails.logger)
        return false unless enabled_for_any_site?

        logger.warn(format_message(message))
        true
      end

      def lifecycle(message, db:, logger: Rails.logger)
        level = enabled?(db: db) ? :warn : :info
        logger.public_send(level, format_message(message, db: db))
      end

      def enabled?(db: nil)
        if db.nil?
          SiteSetting.discord_bot_verbose_logging
        else
          RailsMultisite::ConnectionManagement.with_connection(db) do
            SiteSetting.discord_bot_verbose_logging
          end
        end
      rescue StandardError
        false
      end

      def enabled_for_any_site?
        enabled = false
        RailsMultisite::ConnectionManagement.each_connection do
          enabled ||= SiteSetting.discord_bot_verbose_logging
        end
        enabled
      rescue StandardError
        false
      end

      private

      def format_message(message, db: nil)
        context = db ? "[database=#{db}] " : ""
        "Discord Bot: #{context}#{message}"
      end
    end
  end
end
