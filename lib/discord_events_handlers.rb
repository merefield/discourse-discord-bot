# frozen_string_literal: true
module ::DiscordBot::DiscordEventsHandlers
  # Copy message to Discourse
  module TransmitAnnouncement
    extend Discordrb::EventContainer

    message do |event|
      ::DiscordBot::DiscordEventsHandlers::TransmitAnnouncement.handle_message(event)
    end

    def self.handle_message(event)
      ::DiscordBot::Manager.with_bot_connection(event.bot) do
        target = destination_for(event.message)
        next if target.nil?

        posting_user, raw = ::DiscordBot::Utils.prepare_post(event.message)
        next if raw.blank?

        create_post(posting_user, raw, target)
      end
    end

    def self.destination_for(message)
      if SiteSetting.discord_bot_auto_channel_sync
        category = Category.find_by(name: message.channel.name)
        return destination_for_category(category) if category
      end

      return unless message.channel.id.to_s == SiteSetting.discord_bot_announcement_channel_id
      return if SiteSetting.discord_bot_discourse_announcement_topic_id.blank?

      topic = Topic.find_by(id: SiteSetting.discord_bot_discourse_announcement_topic_id)
      { topic_id: topic.id } if topic
    end

    def self.destination_for_category(category)
      title =
        I18n.t(
          "discord_bot.discord_events.auto_message_copy.default_topic_title",
          channel_name: category.name,
        )
      topic = Topic.find_by(title: title, category_id: category.id)

      topic ? { topic_id: topic.id } : { title: title, category: category.id }
    end

    def self.create_post(posting_user, raw, target)
      PostCreator.create!(posting_user, raw: raw, skip_validations: true, **target)
    end
  end
end
