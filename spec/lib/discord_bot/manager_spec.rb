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
    RailsMultisite::ConnectionManagement.stubs(:establish_connection)
    RailsMultisite::ConnectionManagement.stubs(:each_connection)
    described_class.activate!
  end

  after { described_class.deactivate! }

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

  it "stays stopped outside the dedicated process" do
    described_class.deactivate!

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

  it "terminates a worker that does not stop" do
    worker_started = Queue.new
    keep_running = Queue.new
    stuck_bot = Object.new
    stuck_bot.define_singleton_method(:run) do
      worker_started << Thread.current
      keep_running.pop
    end
    stuck_bot.define_singleton_method(:stop) { raise "stop failed" }
    DiscordBot::Bot.stubs(:init).returns(stuck_bot)

    described_class.restart(db)
    worker_thread = Timeout.timeout(1) { worker_started.pop }
    SiteSetting.discord_bot_enabled = false
    stub_const(described_class, :STOP_TIMEOUT, 0.01) do
      Timeout.timeout(1) { described_class.restart(db) }
    end

    expect(worker_thread).not_to be_alive
  end
end
