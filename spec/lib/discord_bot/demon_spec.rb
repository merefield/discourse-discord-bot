# frozen_string_literal: true

describe DiscordBot::Demon do
  before { described_class.reset_demons }

  it "uses a dedicated process name" do
    expect(described_class.prefix).to eq("discord_bot")
  end

  it "is only required when a site has a configured gateway" do
    SiteSetting.discord_bot_enabled = false
    SiteSetting.discord_bot_token = ""

    expect(described_class.required?).to eq(false)

    SiteSetting.discord_bot_enabled = true
    SiteSetting.discord_bot_token = "token"

    expect(described_class.required?).to eq(true)
  end

  it "does not create a process when no gateway is configured" do
    SiteSetting.discord_bot_enabled = false
    SiteSetting.discord_bot_token = ""

    described_class.start

    expect(described_class.demons).to be_empty
  end

  it "logs a skipped process at warn level when verbose logging is enabled" do
    SiteSetting.discord_bot_enabled = false
    SiteSetting.discord_bot_token = ""
    SiteSetting.discord_bot_verbose_logging = true
    logger = mock
    logger.expects(:warn).with(
      "Discord Bot: Gateway supervisor not spawned because no configured site requires it",
    )

    described_class.start(logger: logger)

    expect(described_class.demons).to be_empty
  end

  it "activates runtimes after acquiring cluster ownership" do
    lease = mock
    lease.expects(:acquire).returns(true)
    lease.expects(:start_renewal)
    DiscordBot::Manager.expects(:activate!)

    expect(described_class.new(0).send(:refresh_ownership, lease, false)).to eq(true)
  end

  it "logs lease acquisition at warn level when verbose logging is enabled" do
    SiteSetting.discord_bot_verbose_logging = true
    lease = mock
    lease.expects(:acquire).returns(true)
    lease.expects(:start_renewal)
    DiscordBot::Manager.expects(:activate!)
    logger = mock
    logger.expects(:warn).with("Discord Bot: Acquired cluster gateway lease")

    expect(described_class.new(0, logger: logger).send(:refresh_ownership, lease, false)).to eq(
      true,
    )
  end

  it "logs standby only once while another process owns the lease" do
    SiteSetting.discord_bot_verbose_logging = true
    lease = mock
    lease.expects(:acquire).twice.returns(false)
    logger = mock
    logger
      .expects(:warn)
      .once
      .with("Discord Bot: Gateway supervisor is standing by because another process owns the lease")
    demon = described_class.new(0, logger: logger)

    expect(
      [demon.send(:refresh_ownership, lease, false), demon.send(:refresh_ownership, lease, false)],
    ).to eq([false, false])
  end

  it "reconciles runtimes while retaining cluster ownership" do
    lease = mock
    lease.expects(:renewing?).returns(true)
    DiscordBot::Manager.expects(:reconcile!)

    expect(described_class.new(0).send(:refresh_ownership, lease, true)).to eq(true)
  end

  it "stops runtimes after losing cluster ownership" do
    lease = mock
    lease.expects(:renewing?).returns(false)
    DiscordBot::Manager.expects(:deactivate!).with(graceful: false)
    logger = mock
    logger.expects(:warn).with("Discord Bot: Gateway ownership lost; force stopping runtimes")

    expect(described_class.new(0, logger: logger).send(:refresh_ownership, lease, true)).to eq(
      false,
    )
  end

  it "force stops runtimes when lease renewal fails" do
    renewal_callback = nil
    lease = Object.new
    lease.define_singleton_method(:acquire) { true }
    lease.define_singleton_method(:start_renewal) { |&callback| renewal_callback = callback }
    DiscordBot::Manager.expects(:activate!)
    logger = mock
    logger.expects(:warn).with("Discord Bot: Gateway ownership lost; force stopping runtimes")

    expect(described_class.new(0, logger: logger).send(:refresh_ownership, lease, false)).to eq(
      true,
    )

    DiscordBot::Manager.expects(:deactivate!).with(graceful: false)
    renewal_callback.call
  end

  it "releases ownership when runtime activation fails" do
    lease = mock
    lease.expects(:acquire).returns(true)
    lease.expects(:start_renewal)
    lease.expects(:stop_renewal)
    lease.expects(:release).returns(true)
    DiscordBot::Manager.expects(:activate!).raises("activation failed")
    DiscordBot::Manager.expects(:deactivate!)
    logger = mock
    logger.expects(:error).with(
      "Discord Bot: Gateway ownership check failed: RuntimeError: activation failed",
    )

    expect(described_class.new(0, logger: logger).send(:refresh_ownership, lease, false)).to eq(
      false,
    )
  end
end
