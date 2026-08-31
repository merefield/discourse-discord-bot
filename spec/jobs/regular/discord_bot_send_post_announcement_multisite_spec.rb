# frozen_string_literal: true

RSpec.describe Jobs::DiscordBotSendPostAnnouncement, type: :multisite do
  before do
    DiscordBot::DiscordrbLoader.load_api
    @original_site_setting_provider = SiteSetting.provider
    SiteSetting.provider = SiteSettings::LocalProcessProvider.new
  end

  after { SiteSetting.provider = @original_site_setting_provider }

  it "delivers an enqueued announcement with its originating site's settings" do
    second_post = nil
    expected_message = nil

    RailsMultisite::ConnectionManagement.with_connection("second") do
      category = Category.first
      second_post = create_post(user: Discourse.system_user, category: category)
      SiteSetting.discord_bot_enabled = true
      SiteSetting.discord_bot_token = "second-token"
      SiteSetting.discord_bot_announcement_channel_id = "second-channel"
      SiteSetting.discord_bot_topic_announcement_categories = category.id.to_s
      SiteSetting.discord_bot_topic_announcement_delay_seconds = 0
      expected_message =
        I18n.t(
          "discord_bot.discourse_events.announce_new_topic",
          posted_category_name: category.name,
          url: Discourse.base_url + second_post.url,
        )
    end

    SiteSetting.discord_bot_enabled = false
    Discordrb::API::Channel.expects(:create_message).with(
      "Bot second-token",
      "second-channel",
      expected_message,
      false,
      nil,
      Digest::SHA256.hexdigest("second:#{second_post.id}").first(25),
      nil,
      nil,
      nil,
      nil,
      nil,
      true,
    )

    described_class.new.perform(post_id: second_post.id, current_site_id: "second")
  ensure
    RailsMultisite::ConnectionManagement.with_connection("second") { second_post&.topic&.destroy! }
  end
end
