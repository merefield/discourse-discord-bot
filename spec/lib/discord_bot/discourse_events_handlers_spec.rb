# frozen_string_literal: true

describe DiscordBot::DiscourseEventsHandlers do
  fab!(:category)
  fab!(:first_post) { create_post(category: category) }
  fab!(:topic) { first_post.topic }
  fab!(:reply) { create_post(topic: topic) }

  let(:bot) { mock("bot") }

  before do
    DiscordBot::Manager.stubs(:bot_for).returns(bot)
    SiteSetting.discord_bot_topic_announcement_categories = category.id.to_s
    SiteSetting.discord_bot_topic_announcement_delay_seconds = 0
  end

  it "registers the post-created handler once" do
    handler_count = DiscourseEvent.events[:post_created].size

    described_class.hook_events
    described_class.hook_events

    expect(DiscourseEvent.events[:post_created].size).to eq(handler_count)
  end

  it "announces only the first post in a topic" do
    message_count = 0
    bot.stubs(:send_message).with { message_count += 1 }

    described_class.send(:handle_post_created, first_post)
    described_class.send(:handle_post_created, reply)

    expect(message_count).to eq(1)
  end
end
