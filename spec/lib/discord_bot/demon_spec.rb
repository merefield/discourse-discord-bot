# frozen_string_literal: true

describe DiscordBot::Demon do
  it "uses a dedicated process name" do
    expect(described_class.prefix).to eq("discord_bot")
  end
end
