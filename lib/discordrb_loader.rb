# frozen_string_literal: true

module ::DiscordBot
  module DiscordrbLoader
    module_function

    def load
      require "discordrb" unless defined?(::Discordrb::Commands::CommandBot)
    end

    def load_api
      return if defined?(::Discordrb::API::Channel)

      require "discordrb/version"
      require "discordrb/api"
      require "discordrb/api/channel"
    end
  end
end
