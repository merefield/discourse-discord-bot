# frozen_string_literal: true

module ::DiscordBot
  # Builds configured Discord bot instances.
  class Bot
    INTENT_NAMES = %i[servers server_members server_messages].freeze
    MESSAGE_CONTENT_INTENT = 1 << 15

    class << self
      def init
        bot =
          Discordrb::Commands::CommandBot.new(
            token: SiteSetting.discord_bot_token,
            prefix: "!",
            intents: gateway_intents,
            ignore_bots: SiteSetting.discord_bot_message_copy_ignore_bot_messages,
          )
        register_ready_event(bot)

        bot.include!(::DiscordBot::DiscordEventsHandlers::TransmitAnnouncement)
        ::DiscordBot::BotCommands.manage_discord_commands(bot)

        bot
      end

      def stop(bot)
        bot.stop
      ensure
        stop_heartbeat(bot)
      end

      def force_stop(bot)
        gateway = bot.gateway if bot.respond_to?(:gateway)
        begin
          gateway&.kill
        ensure
          event_threads(bot).each(&:kill)
        end
      ensure
        stop_heartbeat(bot)
      end

      def event_threads(bot)
        return [] unless bot.respond_to?(:event_threads)

        bot.event_threads&.dup || []
      end

      private

      def gateway_intents
        INTENT_NAMES.sum { |intent| Discordrb::INTENTS.fetch(intent) } | MESSAGE_CONTENT_INTENT
      end

      def stop_heartbeat(bot)
        gateway = bot.gateway if bot.respond_to?(:gateway)
        heartbeat_thread = gateway&.instance_variable_get(:@heartbeat_thread)
        return if heartbeat_thread.nil?

        heartbeat_thread.kill
        heartbeat_thread.join
        gateway.instance_variable_set(:@heartbeat_thread, nil)
      end

      def register_ready_event(bot)
        bot.ready do
          ::DiscordBot::Manager.with_bot_connection(bot) do
            Rails.logger.info(
              "Discord Bot: Logged in as #{bot.profile.username} (ID:#{bot.profile.id}) | #{bot.servers.size} servers",
            )
            bot.send_message(
              SiteSetting.discord_bot_admin_channel_id,
              "The Discourse admin bot has started his shift!",
            )
          end
        end
      end
    end
  end
end
