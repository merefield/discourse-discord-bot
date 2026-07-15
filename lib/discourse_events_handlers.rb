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

      private

      def handle_post_created(post)
        return unless eligible_post?(post)

        bot = current_bot
        return if bot.nil?

        category = post.topic.category
        return if category.nil?

        translation_key = translation_key_for(post, category)
        return if translation_key.nil?

        delay_topic_announcement(translation_key)
        send_announcement(bot, post, category, translation_key)
      end

      def current_bot
        ::DiscordBot::Manager.bot_for(RailsMultisite::ConnectionManagement.current_db)
      end

      def delay_topic_announcement(translation_key)
        return unless translation_key == "discord_bot.discourse_events.announce_new_topic"

        sleep(SiteSetting.discord_bot_topic_announcement_delay_seconds)
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

      def send_announcement(bot, post, category, translation_key)
        message =
          I18n.t(
            translation_key,
            posted_category_name: category.name,
            url: Discourse.base_url + post.url,
          )
        bot.send_message(SiteSetting.discord_bot_announcement_channel_id, message)
      end
    end
  end
end
