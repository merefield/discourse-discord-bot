# frozen_string_literal: true

require "digest"

module Jobs
  class DiscordBotSendPostAnnouncement < ::Jobs::Base
    def execute(args)
      ::DiscordBot::DiscordrbLoader.load
      post = Post.find_by(id: args[:post_id])
      return if post.nil?

      announcement = ::DiscordBot::DiscourseEventsHandlers.announcement_for(post)
      return if announcement.nil?

      Discordrb::API::Channel.create_message(
        discord_token,
        announcement[:channel_id],
        announcement[:message],
        false,
        nil,
        announcement_nonce(post.id),
        nil,
        nil,
        nil,
        nil,
        nil,
        true,
      )
    end

    private

    def discord_token
      "Bot #{SiteSetting.discord_bot_token.delete_prefix("Bot ")}"
    end

    def announcement_nonce(post_id)
      db = RailsMultisite::ConnectionManagement.current_db
      Digest::SHA256.hexdigest("#{db}:#{post_id}").first(25)
    end
  end
end
