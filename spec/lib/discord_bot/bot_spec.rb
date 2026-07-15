# frozen_string_literal: true

describe DiscordBot::Bot do
  before { SiteSetting.discord_bot_token = "token" }

  it "registers the supported commands" do
    bot = described_class.init

    expect(bot.commands.keys).to include(:disccopy, :disckick, :discsync)
  end
end
