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
end
