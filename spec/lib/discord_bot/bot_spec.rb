# frozen_string_literal: true

describe DiscordBot::Bot do
  before { SiteSetting.discord_bot_token = "token" }

  it "registers the supported commands" do
    bot = described_class.init

    expect(bot.commands.keys).to include(:disccopy, :disckick, :discsync)
  end

  it "terminates the gateway heartbeat when stopping" do
    heartbeat_thread = Thread.new { sleep }
    gateway = Object.new
    gateway.instance_variable_set(:@heartbeat_thread, heartbeat_thread)
    bot = stub(gateway: gateway, stop: nil)

    described_class.stop(bot)

    expect(heartbeat_thread).not_to be_alive
    expect(gateway.instance_variable_get(:@heartbeat_thread)).to be_nil
  end
end
