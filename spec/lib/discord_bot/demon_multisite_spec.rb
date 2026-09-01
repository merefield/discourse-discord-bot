# frozen_string_literal: true

RSpec.describe DiscordBot::Demon, type: :multisite do
  before do
    @original_site_setting_provider = SiteSetting.provider
    SiteSetting.provider = SiteSettings::LocalProcessProvider.new
    RailsMultisite::ConnectionManagement.each_connection do
      SiteSetting.discord_bot_enabled = false
      SiteSetting.discord_bot_token = ""
    end
  end

  after { SiteSetting.provider = @original_site_setting_provider }

  it "is required when only a secondary site has a configured gateway" do
    expect(described_class.required?).to eq(false)

    RailsMultisite::ConnectionManagement.with_connection("second") do
      SiteSetting.discord_bot_enabled = true
      SiteSetting.discord_bot_token = "second-token"
    end

    expect(described_class.required?).to eq(true)
  end
end
