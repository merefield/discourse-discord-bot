# frozen_string_literal: true

RSpec.describe DiscordBot::Manager, type: :multisite do
  before do
    @original_site_setting_provider = SiteSetting.provider
    SiteSetting.provider = SiteSettings::LocalProcessProvider.new
    described_class.deactivate!

    RailsMultisite::ConnectionManagement.each_connection do
      SiteSetting.discord_bot_enabled = true
      SiteSetting.discord_bot_token = "#{RailsMultisite::ConnectionManagement.current_db}-token"
    end
  end

  after do
    described_class.deactivate!
    SiteSetting.provider = @original_site_setting_provider
  end

  it "maintains and routes independently configured runtimes for every site" do
    bots =
      Array.new(2) do
        stopped = Queue.new
        Object.new.tap do |bot|
          bot.define_singleton_method(:run) { stopped.pop }
          bot.define_singleton_method(:stop) { stopped << true }
          bot.define_singleton_method(:event_threads) { [] }
        end
      end
    DiscordBot::Bot.stubs(:init).returns(*bots)

    configured_tokens = {}
    RailsMultisite::ConnectionManagement.each_connection do |db|
      configured_tokens[db] = SiteSetting.discord_bot_token
    end
    expect(configured_tokens).to eq("default" => "default-token", "second" => "second-token")

    described_class.activate!

    bots_by_db = {
      "default" => described_class.bot_for("default"),
      "second" => described_class.bot_for("second"),
    }
    expect(bots_by_db.values).to eq(bots)

    routed_databases =
      bots_by_db.to_h do |db, bot|
        routed_db = nil
        described_class.with_bot_connection(bot) do
          routed_db = RailsMultisite::ConnectionManagement.current_db
        end
        [db, routed_db]
      end

    expect(routed_databases).to eq("default" => "default", "second" => "second")
  end
end
