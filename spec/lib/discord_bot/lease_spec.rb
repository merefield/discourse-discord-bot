# frozen_string_literal: true

describe DiscordBot::Lease do
  let(:redis) { Discourse.redis.without_namespace }
  let(:key) { "discord_bot:test_gateway_owner:#{SecureRandom.hex(8)}" }
  let(:owner) { described_class.new(redis: redis, key: key, token: "owner") }
  let(:contender) { described_class.new(redis: redis, key: key, token: "contender") }

  after { redis.del(key) }

  it "allows only the owner to renew and release the lease" do
    expect(owner.acquire).to eq(true)
    expect(contender.acquire).to eq(false)
    expect(contender.renew).to eq(false)
    expect(contender.release).to eq(false)
    expect(owner.renew).to eq(true)
    expect(owner.release).to eq(true)
    expect(contender.acquire).to eq(true)
  end

  it "renews independently until ownership is lost" do
    lease = described_class.new(redis: redis, key: key, token: "owner", refresh_seconds: 0.01)
    ownership_lost = Queue.new
    expect(lease.acquire).to eq(true)

    lease.start_renewal { ownership_lost << true }
    redis.del(key)

    expect(Timeout.timeout(1) { ownership_lost.pop }).to eq(true)
    Timeout.timeout(1) { Thread.pass while lease.renewing? }
    expect(lease.renewing?).to eq(false)
  ensure
    lease&.stop_renewal
  end
end
