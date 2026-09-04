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

  it "does not start a runtime after deactivation begins" do
    restart_ready = Queue.new
    continue_restart = Queue.new
    RailsMultisite::ConnectionManagement
      .stubs(:with_connection)
      .with do |database|
        restart_ready << true
        continue_restart.pop
        database == db
      end
      .yields
    DiscordBot::Bot.expects(:init).never

    restart_thread = Thread.new { described_class.restart(db) }
    Timeout.timeout(1) { restart_ready.pop }
    described_class.deactivate!
    continue_restart << true
    Timeout.timeout(1) { restart_thread.join }

    expect(described_class.bot_for(db)).to be_nil
  ensure
    continue_restart << true if continue_restart&.empty?
    restart_thread&.kill
    restart_thread&.join
  end

  it "does not replace a runtime after ownership is revoked during shutdown" do
    worker_started = Queue.new
    stop_started = Queue.new
    allow_stop = Queue.new
    worker_stopped = Queue.new
    first_bot = Object.new
    first_bot.define_singleton_method(:run) do
      worker_started << true
      worker_stopped.pop
    end
    first_bot.define_singleton_method(:stop) do
      stop_started << true
      allow_stop.pop
      worker_stopped << true
    end
    first_bot.define_singleton_method(:event_threads) { [] }
    second_bot = bots.second
    DiscordBot::Bot.stubs(:init).returns(first_bot, second_bot)

    described_class.restart(db)
    Timeout.timeout(1) { worker_started.pop }
    restart_thread = Thread.new { described_class.restart(db) }
    Timeout.timeout(1) { stop_started.pop }
    deactivation_thread = Thread.new { described_class.deactivate!(graceful: false) }
    Timeout.timeout(1) { Thread.pass until deactivation_thread.status == "sleep" }
    allow_stop << true

    expect(Timeout.timeout(1) { restart_thread.value }).to be_nil
    Timeout.timeout(1) { deactivation_thread.join }
    expect(described_class.bot_for(db)).to be_nil
  ensure
    allow_stop << true if allow_stop&.empty?
    restart_thread&.kill
    restart_thread&.join
    deactivation_thread&.kill
    deactivation_thread&.join
  end

  it "restarts a site's runtime when its gateway configuration changes" do
    DiscordBot::Bot.stubs(:init).returns(*bots)
    described_class.restart(db)
    RailsMultisite::ConnectionManagement.stubs(:each_connection).yields(db)

    SiteSetting.discord_bot_token = "new-token"
    described_class.reconcile!

    expect(described_class.bot_for(db)).to eq(bots.second)
  end

  it "restarts a site's runtime when its admin role changes" do
    DiscordBot::Bot.stubs(:init).returns(*bots)
    described_class.restart(db)
    RailsMultisite::ConnectionManagement.stubs(:each_connection).yields(db)

    SiteSetting.discord_bot_admin_role_id = "new-role"
    described_class.reconcile!

    expect(described_class.bot_for(db)).to eq(bots.second)
  end

  it "keeps the gateway running when its history-copy filtering changes" do
    DiscordBot::Bot.stubs(:init).returns(bots.first)
    described_class.restart(db)
    RailsMultisite::ConnectionManagement.stubs(:each_connection).yields(db)

    SiteSetting.discord_bot_message_copy_ignore_bot_messages = false
    described_class.reconcile!

    expect(described_class.bot_for(db)).to eq(bots.first)
  end

  it "logs per-site gateway lifecycle details at warn level when verbose logging is enabled" do
    SiteSetting.discord_bot_verbose_logging = true
    DiscordBot::Bot.stubs(:init).returns(bots.first)
    Rails.logger.expects(:warn).with("Discord Bot: [database=#{db}] Starting gateway runtime")
    Rails.logger.expects(:warn).with("Discord Bot: [database=#{db}] Stopping gateway runtime")
    Rails.logger.expects(:warn).with("Discord Bot: [database=#{db}] Stopped gateway runtime")

    described_class.restart(db)
    described_class.deactivate!

    expect(described_class.bot_for(db)).to be_nil
  end

  it "clears a runtime when its worker exits" do
    failed_bot = mock("failed bot").tap { |bot| bot.stubs(:run).raises("connection failed") }
    DiscordBot::Bot.stubs(:init).returns(failed_bot)
    Rails
      .logger
      .expects(:error)
      .with("Discord Bot: [database=#{db}] Gateway runtime failed: RuntimeError: connection failed")
    Rails
      .logger
      .expects(:warn)
      .with("Discord Bot: [database=#{db}] Gateway runtime exited unexpectedly")

    described_class.restart(db)
    Timeout.timeout(1) { Thread.pass until described_class.bot_for(db).nil? }

    expect(described_class.bot_for(db)).to be_nil
  end

  it "terminates Discord-owned threads when graceful shutdown fails" do
    worker_started = Queue.new
    websocket_started = Queue.new
    event_started = Queue.new
    gateway = Object.new
    websocket_thread = nil
    gateway.define_singleton_method(:run) do
      websocket_thread =
        Thread.new do
          websocket_started << true
          sleep
        end
      gateway.instance_variable_set(:@ws_thread, websocket_thread)
      websocket_thread.join
    end
    gateway.define_singleton_method(:kill) { websocket_thread&.kill }

    stuck_bot = Object.new
    event_thread =
      Thread.new do
        event_started << true
        sleep
      end
    stuck_bot.define_singleton_method(:gateway) { gateway }
    stuck_bot.define_singleton_method(:event_threads) { [event_thread] }
    stuck_bot.define_singleton_method(:run) do
      worker_started << Thread.current
      gateway.run
    end
    stuck_bot.define_singleton_method(:stop) { raise "stop failed" }
    DiscordBot::Bot.stubs(:init).returns(stuck_bot)

    described_class.restart(db)
    worker_thread = Timeout.timeout(1) { worker_started.pop }
    Timeout.timeout(1) { websocket_started.pop }
    Timeout.timeout(1) { event_started.pop }
    SiteSetting.discord_bot_enabled = false
    stub_const(described_class, :STOP_TIMEOUT, 0.01) do
      Timeout.timeout(1) { described_class.restart(db) }
    end

    expect([worker_thread, websocket_thread, event_thread]).to all(
      satisfy { |thread| !thread.alive? },
    )
  ensure
    [worker_thread, websocket_thread, event_thread].compact.each do |thread|
      thread.kill
      thread.join
    end
  end

  it "bypasses a blocking graceful shutdown when force stopping" do
    worker_started = Queue.new
    allow_graceful_stop = Queue.new
    deactivation_finished = Queue.new
    blocking_bot = Object.new
    blocking_bot.define_singleton_method(:run) do
      worker_started << Thread.current
      sleep
    end
    blocking_bot.define_singleton_method(:stop) { allow_graceful_stop.pop }
    blocking_bot.define_singleton_method(:event_threads) { [] }
    DiscordBot::Bot.stubs(:init).returns(blocking_bot)

    described_class.restart(db)
    worker_thread = Timeout.timeout(1) { worker_started.pop }
    deactivation_thread =
      Thread.new do
        described_class.deactivate!(graceful: false)
        deactivation_finished << true
      end

    expect(Timeout.timeout(1) { deactivation_finished.pop }).to eq(true)
    expect(worker_thread).not_to be_alive
  ensure
    allow_graceful_stop << true if allow_graceful_stop&.empty?
    deactivation_thread&.kill
    deactivation_thread&.join
    worker_thread&.kill
    worker_thread&.join
  end
end
