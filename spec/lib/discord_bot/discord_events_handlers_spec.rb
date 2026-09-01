# frozen_string_literal: true

describe DiscordBot::DiscordEventsHandlers::TransmitAnnouncement do
  fab!(:user)
  fab!(:topic)

  let(:channel) { stub(id: 456, name: "discord") }
  let(:message) { stub(channel: channel) }
  let(:bot) { stub }
  let(:event) { stub(message: message, bot: bot) }

  before do
    SiteSetting.discord_bot_auto_channel_sync = false
    SiteSetting.discord_bot_announcement_channel_id = "123"
    SiteSetting.discord_bot_discourse_announcement_topic_id = ""
    DiscordBot::Manager.stubs(:with_bot_connection).with(bot).yields
  end

  it "skips messages from unrelated channels" do
    expect { described_class.handle_message(event) }.not_to change(Post, :count)
  end

  it "copies messages to the configured announcement topic" do
    channel.stubs(:id).returns(123)
    SiteSetting.discord_bot_discourse_announcement_topic_id = topic.id.to_s
    DiscordBot::Utils.stubs(:prepare_post).with(message).returns([user, "From Discord"])

    expect { described_class.handle_message(event) }.to change { topic.posts.count }.by(1)
  end

  it "checks the destination before preparing a message" do
    DiscordBot::Utils.expects(:prepare_post).never

    described_class.handle_message(event)
  end
end
