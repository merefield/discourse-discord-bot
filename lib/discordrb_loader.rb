# frozen_string_literal: true

module ::DiscordBot
  module DiscordrbLoader
    module_function

    def load
      require "discordrb" unless defined?(::Discordrb::Commands::CommandBot)
    end
  end
end
