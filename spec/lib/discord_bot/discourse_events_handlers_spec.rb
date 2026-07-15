# frozen_string_literal: true

describe DiscordBot::DiscourseEventsHandlers do
  fab!(:category)
  fab!(:first_post) { create_post(category: category) }
  fab!(:topic) { first_post.topic }
  fab!(:reply) { create_post(topic: topic) }
  fab!(:private_message_post)

  let(:announcements) { [] }

  let(:bot) do
    mock("bot").tap do |bot|
      bot.stubs(:send_message).with { |channel_id, message| announcements << [channel_id, message] }
    end
  end

  before do
    DiscordBot::Manager.stubs(:bot_for).returns(bot)
    SiteSetting.discord_bot_announcement_channel_id = "123"
    SiteSetting.discord_bot_topic_announcement_categories = category.id.to_s
    SiteSetting.discord_bot_topic_announcement_delay_seconds = 0
  end

  it "registers the post-created handler once" do
    handler_count = DiscourseEvent.events[:post_created].size

    described_class.hook_events
    described_class.hook_events

    expect(DiscourseEvent.events[:post_created].size).to eq(handler_count)
  end

  it "announces only the first post as a new topic" do
    described_class.handle_post_created(first_post)
    described_class.handle_post_created(reply)

    expect(announcements).to contain_exactly(
      [
        SiteSetting.discord_bot_announcement_channel_id,
        I18n.t(
          "discord_bot.discourse_events.announce_new_topic",
          posted_category_name: category.name,
          url: Discourse.base_url + first_post.url,
        ),
      ],
    )
  end

  it "announces every post in a post category" do
    SiteSetting.discord_bot_post_announcement_categories = category.id.to_s

    described_class.handle_post_created(first_post)
    described_class.handle_post_created(reply)

    expected_messages =
      [first_post, reply].map do |post|
        [
          SiteSetting.discord_bot_announcement_channel_id,
          I18n.t(
            "discord_bot.discourse_events.announce_new_post",
            posted_category_name: category.name,
            url: Discourse.base_url + post.url,
          ),
        ]
      end

    expect(announcements).to contain_exactly(*expected_messages)
  end

  it "skips posts outside configured categories" do
    SiteSetting.discord_bot_topic_announcement_categories = ""

    described_class.handle_post_created(first_post)

    expect(announcements).to be_empty
  end

  it "skips private messages" do
    described_class.handle_post_created(private_message_post)

    expect(announcements).to be_empty
  end

  it "skips announcements without an active bot" do
    DiscordBot::Manager.stubs(:bot_for).returns(nil)

    described_class.handle_post_created(first_post)

    expect(announcements).to be_empty
  end
end
