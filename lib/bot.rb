# frozen_string_literal: true

module ::DiscordBot
  # Builds configured Discord bot instances.
  class Bot
    INTENTS = %i[servers server_members server_messages].freeze

    class << self
      def init
        bot =
          Discordrb::Commands::CommandBot.new(
            token: SiteSetting.discord_bot_token,
            prefix: "!",
            intents: INTENTS,
            ignore_bots: SiteSetting.discord_bot_message_copy_ignore_bot_messages,
          )
        register_ready_event(bot)

        bot.include!(::DiscordBot::DiscordEventsHandlers::TransmitAnnouncement)
        ::DiscordBot::BotCommands.manage_discord_commands(bot)

        bot
      end

      def stop(bot)
        bot.stop

        gateway = bot.gateway if bot.respond_to?(:gateway)
        heartbeat_thread = gateway&.instance_variable_get(:@heartbeat_thread)
        return if heartbeat_thread.nil?

        heartbeat_thread.kill
        heartbeat_thread.join
        gateway.instance_variable_set(:@heartbeat_thread, nil)
      end

      private

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
