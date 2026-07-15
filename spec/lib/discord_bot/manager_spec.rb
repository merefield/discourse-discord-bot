# frozen_string_literal: true

describe DiscordBot::Manager do
  let(:db) { RailsMultisite::ConnectionManagement.current_db }
  let(:bots) { Array.new(2) { mock("bot").tap { |bot| bot.stubs(run: nil, stop: nil) } } }

  before do
    SiteSetting.discord_bot_enabled = true
    SiteSetting.discord_bot_token = "token"
    Discourse.stubs(:running_in_rack?).returns(true)
    RailsMultisite::ConnectionManagement.stubs(:establish_connection)
  end

  after { described_class.stop_all }

  it "replaces the active runtime" do
    DiscordBot::Bot.stubs(:init).returns(bots.first, bots.second)

    described_class.restart(db)
    described_class.restart(db)

    expect(described_class.bot_for(db)).to eq(bots.second)
  end

  it "stops the runtime when disabled" do
    DiscordBot::Bot.stubs(:init).returns(bots.first)
    described_class.restart(db)

    SiteSetting.discord_bot_enabled = false
    described_class.restart(db)

    expect(described_class.bot_for(db)).to be_nil
  end

  it "stays stopped without a token" do
    SiteSetting.discord_bot_token = ""

    described_class.restart(db)

    expect(described_class.bot_for(db)).to be_nil
  end

  it "stays stopped outside a web server process" do
    Discourse.stubs(:running_in_rack?).returns(false)

    described_class.restart(db)

    expect(described_class.bot_for(db)).to be_nil
  end

  it "keeps a runtime for each multisite database" do
    DiscordBot::Bot.stubs(:init).returns(*bots)

    described_class.restart("first")
    described_class.restart("second")

    expect([described_class.bot_for("first"), described_class.bot_for("second")]).to eq(bots)
  end
end
