# frozen_string_literal: true

describe DiscordBot::Manager do
  let(:db) { RailsMultisite::ConnectionManagement.current_db }

  let(:bots) do
    Array.new(2) do
      stopped = Queue.new
      mock("bot").tap do |bot|
        bot.stubs(:run) { stopped.pop }
        bot.stubs(:stop) { stopped << true }
      end
    end
  end

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

  it "clears a runtime when its worker exits" do
    failed_bot = mock("failed bot").tap { |bot| bot.stubs(:run).raises("connection failed") }
    DiscordBot::Bot.stubs(:init).returns(failed_bot)

    described_class.restart(db)
    Timeout.timeout(1) { Thread.pass until described_class.bot_for(db).nil? }

    expect(described_class.bot_for(db)).to be_nil
  end
end
