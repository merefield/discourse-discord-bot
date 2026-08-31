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

  it "activates runtimes after acquiring cluster ownership" do
    lease = mock
    lease.expects(:acquire).returns(true)
    lease.expects(:start_renewal)
    DiscordBot::Manager.expects(:activate!)

    expect(described_class.new(0).send(:refresh_ownership, lease, false)).to eq(true)
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

    expect(described_class.new(0).send(:refresh_ownership, lease, true)).to eq(false)
  end

  it "force stops runtimes when lease renewal fails" do
    renewal_callback = nil
    lease = Object.new
    lease.define_singleton_method(:acquire) { true }
    lease.define_singleton_method(:start_renewal) { |&callback| renewal_callback = callback }
    DiscordBot::Manager.expects(:activate!)

    expect(described_class.new(0).send(:refresh_ownership, lease, false)).to eq(true)

    DiscordBot::Manager.expects(:deactivate!).with(graceful: false)
    renewal_callback.call
  end

  it "releases ownership when runtime activation fails" do
    lease = mock
    lease.expects(:acquire).returns(true)
    lease.expects(:start_renewal)
    lease.expects(:stop_renewal)
    lease.expects(:release)
    DiscordBot::Manager.expects(:activate!).raises("activation failed")
    DiscordBot::Manager.expects(:deactivate!)

    expect(described_class.new(0).send(:refresh_ownership, lease, false)).to eq(false)
  end
end
