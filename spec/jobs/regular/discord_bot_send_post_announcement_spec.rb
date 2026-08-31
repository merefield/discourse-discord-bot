# frozen_string_literal: true

describe Jobs::DiscordBotSendPostAnnouncement do
  fab!(:category)
  let(:post) { create_post(category: category) }

  before do
    SiteSetting.discord_bot_enabled = true
    SiteSetting.discord_bot_token = "token"
    SiteSetting.discord_bot_announcement_channel_id = "123"
    SiteSetting.discord_bot_topic_announcement_categories = category.id.to_s
    SiteSetting.discord_bot_topic_announcement_delay_seconds = 0
  end

  it "delivers the current site's announcement" do
    Discordrb::API::Channel.expects(:create_message).with(
      "Bot token",
      SiteSetting.discord_bot_announcement_channel_id,
      I18n.t(
        "discord_bot.discourse_events.announce_new_topic",
        posted_category_name: category.name,
        url: Discourse.base_url + post.url,
      ),
    )

    described_class.new.execute(post_id: post.id)
  end

  it "skips delivery when the site is disabled before execution" do
    SiteSetting.discord_bot_enabled = false
    Discordrb::API::Channel.expects(:create_message).never

    described_class.new.execute(post_id: post.id)
  end
end
