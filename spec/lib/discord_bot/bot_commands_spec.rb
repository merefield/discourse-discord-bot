# frozen_string_literal: true

describe DiscordBot::BotCommands do
  describe ".fetch_history" do
    it "accumulates paginated history up to the requested count" do
      requests = []
      next_id = 300
      message_class = Struct.new(:id)
      channel = Object.new
      channel.define_singleton_method(:history) do |count, before_id|
        requests << [count, before_id]
        Array.new(count) { message_class.new(next_id -= 1) }
      end

      messages = described_class.fetch_history(channel, 500, 250)

      expect(messages.size).to eq(250)
      expect(requests).to eq([[100, 500], [100, 200], [50, 100]])
    end

    it "stops requesting pages after reaching the start of history" do
      channel = mock
      channel.expects(:history).with(100, 500).returns([stub(id: 499)])

      expect(described_class.fetch_history(channel, 500, 200).size).to eq(1)
    end
  end

  it "bounds the configured message limit" do
    expect { SiteSetting.discord_bot_message_copy_max_messages = 10_001 }.to raise_error(
      Discourse::InvalidParameters,
    )
  end
end
