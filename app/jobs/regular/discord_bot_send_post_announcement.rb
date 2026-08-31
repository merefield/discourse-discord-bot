# frozen_string_literal: true

module Jobs
  class DiscordBotSendPostAnnouncement < ::Jobs::Base
    def execute(args)
      post = Post.find_by(id: args[:post_id])
      return if post.nil?

      announcement = ::DiscordBot::DiscourseEventsHandlers.announcement_for(post)
      return if announcement.nil?

      Discordrb::API::Channel.create_message(
        discord_token,
        announcement[:channel_id],
        announcement[:message],
      )
    end

    private

    def discord_token
      "Bot #{SiteSetting.discord_bot_token.delete_prefix("Bot ")}"
    end
  end
end
