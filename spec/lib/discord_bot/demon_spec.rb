# frozen_string_literal: true

describe DiscordBot::Demon do
  it "uses a dedicated process name" do
    expect(described_class.prefix).to eq("discord_bot")
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

    expect(described_class.new(0).send(:refresh_ownership, lease, true)).to eq(false)
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
