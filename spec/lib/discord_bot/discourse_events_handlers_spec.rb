# frozen_string_literal: true

describe DiscordBot::DiscourseEventsHandlers do
  fab!(:category)
  fab!(:first_post) { create_post(category: category) }
  fab!(:topic) { first_post.topic }
  fab!(:reply) { create_post(topic: topic) }
  fab!(:private_message_post)

  before do
    SiteSetting.discord_bot_enabled = true
    SiteSetting.discord_bot_token = "token"
    SiteSetting.discord_bot_announcement_channel_id = "123"
    SiteSetting.discord_bot_topic_announcement_categories = category.id.to_s
    SiteSetting.discord_bot_topic_announcement_delay_seconds = 5
  end

  it "registers the post-created handler once" do
    handler_count = DiscourseEvent.events[:post_created].size

    described_class.hook_events
    described_class.hook_events

    expect(DiscourseEvent.events[:post_created].size).to eq(handler_count)
  end

  it "queues only the first post as a delayed topic announcement" do
    described_class.handle_post_created(first_post)
    described_class.handle_post_created(reply)

    expect(Jobs::DiscordBotSendPostAnnouncement.jobs.size).to eq(1)
    expect(Jobs::DiscordBotSendPostAnnouncement.jobs.first["args"].first).to include(
      "post_id" => first_post.id,
    )
  end

  it "queues every post in a post category" do
    SiteSetting.discord_bot_post_announcement_categories = category.id.to_s

    described_class.handle_post_created(first_post)
    described_class.handle_post_created(reply)

    expect(Jobs::DiscordBotSendPostAnnouncement.jobs.size).to eq(2)
  end

  it "skips posts outside configured categories and private messages" do
    SiteSetting.discord_bot_topic_announcement_categories = ""

    described_class.handle_post_created(first_post)
    described_class.handle_post_created(private_message_post)

    expect(Jobs::DiscordBotSendPostAnnouncement.jobs).to be_empty
  end

  it "skips announcements without complete configuration" do
    SiteSetting.discord_bot_token = ""

    described_class.handle_post_created(first_post)

    expect(Jobs::DiscordBotSendPostAnnouncement.jobs).to be_empty
  end
end
