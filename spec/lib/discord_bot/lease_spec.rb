# frozen_string_literal: true

describe DiscordBot::Lease do
  let(:redis) { Discourse.redis.without_namespace }
  let(:key) { "discord_bot:test_gateway_owner:#{SecureRandom.hex(8)}" }
  let(:owner) { described_class.new(redis: redis, key: key, token: "owner") }
  let(:contender) { described_class.new(redis: redis, key: key, token: "contender") }

  after { redis.del(key, Discourse.redis.namespace_key(key)) }

  it "keeps the default lease inside the deployment namespace" do
    lease = described_class.new(key: key, token: "owner")
    namespaced_key = Discourse.redis.namespace_key(key)

    expect(lease.acquire).to eq(true)
    expect(lease.renew).to eq(true)
    expect(redis.mget(key, namespaced_key)).to eq([nil, "owner"])
    expect(lease.release).to eq(true)
  end

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

  it "notifies ownership loss once when the callback raises" do
    lease = described_class.new(redis: redis, key: key, token: "owner", refresh_seconds: 0.01)
    callback_calls = Queue.new
    original_report_on_exception = Thread.report_on_exception
    Thread.report_on_exception = false
    expect(lease.acquire).to eq(true)

    lease.start_renewal do
      callback_calls << true
      raise "cleanup failed"
    end
    redis.del(key)
    Timeout.timeout(1) { Thread.pass while lease.renewing? }

    expect(callback_calls.size).to eq(1)
  ensure
    Thread.report_on_exception = original_report_on_exception
  end
end
