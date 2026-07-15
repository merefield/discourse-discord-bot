# frozen_string_literal: true

module ::DiscordBot
  # Builds configured Discord bot instances.
  class Bot
    class << self
      def init
        bot = Discordrb::Commands::CommandBot.new token: SiteSetting.discord_bot_token, prefix: "!"
        register_ready_event(bot)

        bot.include!(::DiscordBot::DiscordEventsHandlers::TransmitAnnouncement)
        ::DiscordBot::BotCommands.manage_discord_commands(bot)

        bot
      end

      private

      def register_ready_event(bot)
        bot.ready do
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
