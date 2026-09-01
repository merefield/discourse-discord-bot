# frozen_string_literal: true

describe DiscordBot::LifecycleLogger do
  let(:output) { StringIO.new }
  let(:logger) { Logger.new(output) }

  it "writes verbose diagnostics at warn level only when enabled" do
    expect(SiteSetting.discord_bot_verbose_logging).to eq(false)

    expect(
      described_class.verbose("Starting gateway runtime", db: "default", logger: logger),
    ).to eq(false)
    expect(output.string).to be_empty

    SiteSetting.discord_bot_verbose_logging = true

    expect(
      described_class.verbose("Starting gateway runtime", db: "default", logger: logger),
    ).to eq(true)
    expect(output.string).to include(
      "WARN",
      "Discord Bot: [database=default] Starting gateway runtime",
    )
  end

  it "promotes standard lifecycle messages to warn level when verbose logging is enabled" do
    SiteSetting.discord_bot_verbose_logging = false
    described_class.lifecycle("Logged in", db: "default", logger: logger)

    SiteSetting.discord_bot_verbose_logging = true
    described_class.lifecycle("Logged in", db: "default", logger: logger)

    expect(output.string.lines.grep(/Logged in/).map { |line| line[/\b(?:INFO|WARN)\b/] }).to eq(
      %w[INFO WARN],
    )
  end
end
