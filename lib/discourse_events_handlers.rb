# frozen_string_literal: true

module ::DiscordBot
  # Sends configured Discourse post notifications to Discord.
  module DiscourseEventsHandlers
    class << self
      def hook_events
        return if @post_created_handler

        @post_created_handler = proc { |post| handle_post_created(post) }
        DiscourseEvent.on(:post_created, &@post_created_handler)
      end

      def handle_post_created(post)
        announcement = announcement_for(post)
        return if announcement.nil?

        Jobs.enqueue_in(announcement[:delay], :discord_bot_send_post_announcement, post_id: post.id)
      end

      def announcement_for(post)
        return unless SiteSetting.discord_bot_enabled
        return if SiteSetting.discord_bot_token.blank?
        return if SiteSetting.discord_bot_announcement_channel_id.blank?
        return unless eligible_post?(post)

        category = post.topic.category
        return if category.nil?

        translation_key = translation_key_for(post, category)
        return if translation_key.nil?

        {
          channel_id: SiteSetting.discord_bot_announcement_channel_id,
          delay: announcement_delay(translation_key),
          message:
            I18n.t(
              translation_key,
              posted_category_name: category.name,
              url: Discourse.base_url + post.url,
            ),
        }
      end

      private

      def announcement_delay(translation_key)
        return 0 unless translation_key == "discord_bot.discourse_events.announce_new_topic"

        SiteSetting.discord_bot_topic_announcement_delay_seconds.seconds
      end

      def eligible_post?(post)
        post.id.positive? && post.topic.archetype != "private_message"
      end

      def post_categories
        SiteSetting.discord_bot_post_announcement_categories.split("|")
      end

      def topic_categories
        SiteSetting.discord_bot_topic_announcement_categories.split("|")
      end

      def translation_key_for(post, category)
        if post_categories.include?(category.id.to_s)
          return "discord_bot.discourse_events.announce_new_post"
        end

        return unless post.post_number == 1 && topic_categories.include?(category.id.to_s)

        "discord_bot.discourse_events.announce_new_topic"
      end
    end
  end
end
