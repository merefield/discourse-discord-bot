# frozen_string_literal: true

require "open3"

describe DiscordBot::DiscordrbLoader do
  it "supports Discord API failures without loading the gateway" do
    loader_path = File.expand_path("../../../lib/discordrb_loader.rb", __dir__)
    gem_load_paths = Gem.loaded_specs.values.flat_map(&:full_require_paths).uniq
    script = <<~RUBY
      module DiscordBot
      end

      load #{loader_path.inspect}
      DiscordBot::DiscordrbLoader.load_api

      request_count = 0
      RestClient.define_singleton_method(:get) do
        request_count += 1
        raise RestClient::BadGateway if request_count == 1

        :ok
      end

      raise "API retry failed" unless Discordrb::API.raw_request(:get, []) == :ok
      raise "gateway loaded by API path" if defined?(Discordrb::Commands::CommandBot)

      api_logger = Discordrb::LOGGER
      DiscordBot::DiscordrbLoader.load
      raise "gateway failed to load" unless defined?(Discordrb::Commands::CommandBot)
      raise "API logger was not replaced" if Discordrb::LOGGER.equal?(api_logger)
    RUBY

    _stdout, stderr, status =
      Open3.capture3(
        { "RUBYLIB" => gem_load_paths.join(File::PATH_SEPARATOR) },
        RbConfig.ruby,
        "-e",
        script,
      )

    expect(status).to be_success, stderr
    expect(stderr).not_to include("already initialized constant Discordrb::LOGGER")
  end
end
