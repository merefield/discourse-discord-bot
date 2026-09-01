# frozen_string_literal: true

RSpec.describe DiscordBot::LifecycleLogger, type: :multisite do
  before do
    @original_site_setting_provider = SiteSetting.provider
    SiteSetting.provider = SiteSettings::LocalProcessProvider.new
    RailsMultisite::ConnectionManagement.each_connection do
      SiteSetting.discord_bot_verbose_logging = false
    end
  end

  after { SiteSetting.provider = @original_site_setting_provider }

  it "enables process diagnostics when a secondary site requests verbose logging" do
    RailsMultisite::ConnectionManagement.with_connection("second") do
      SiteSetting.discord_bot_verbose_logging = true
    end
    output = StringIO.new

    expect(
      described_class.verbose_for_any_site(
        "Gateway supervisor is ready",
        logger: Logger.new(output),
      ),
    ).to eq(true)
    expect(output.string).to include("WARN", "Discord Bot: Gateway supervisor is ready")
  end
end
