# frozen_string_literal: true

describe DiscordBot::Bot do
  before { SiteSetting.discord_bot_token = "token" }

  it "registers the supported commands" do
    bot = described_class.init

    expect(bot.commands.keys).to include(:disccopy, :disckick, :discsync)
    expect(bot.gateway.intents).to eq(
      DiscordBot::Bot::INTENT_NAMES.sum { |intent| Discordrb::INTENTS.fetch(intent) } |
        DiscordBot::Bot::MESSAGE_CONTENT_INTENT,
    )
    expect(bot.gateway.intents & (1 << 15)).to eq(1 << 15)
    expect(bot.instance_variable_get(:@ignore_bots)).to eq(true)
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

  it "terminates the gateway heartbeat when bot shutdown fails" do
    heartbeat_thread = Thread.new { sleep }
    gateway = Object.new
    gateway.instance_variable_set(:@heartbeat_thread, heartbeat_thread)
    bot = stub(gateway: gateway)
    bot.stubs(:stop).raises("shutdown failed")

    expect { described_class.stop(bot) }.to raise_error("shutdown failed")
    expect(heartbeat_thread).not_to be_alive
    expect(gateway.instance_variable_get(:@heartbeat_thread)).to be_nil
  ensure
    heartbeat_thread&.kill
    heartbeat_thread&.join
  end

  it "force stops websocket and event threads" do
    websocket_thread = Thread.new { sleep }
    event_thread = Thread.new { sleep }
    heartbeat_thread = Thread.new { sleep }
    gateway = stub(kill: websocket_thread.kill)
    gateway.instance_variable_set(:@heartbeat_thread, heartbeat_thread)
    bot = stub(gateway: gateway, event_threads: [event_thread])

    described_class.force_stop(bot)
    websocket_thread.join
    event_thread.join

    expect([websocket_thread, event_thread, heartbeat_thread]).to all(
      satisfy { |thread| !thread.alive? },
    )
  ensure
    [websocket_thread, event_thread, heartbeat_thread].compact.each do |thread|
      thread.kill
      thread.join
    end
  end
end
