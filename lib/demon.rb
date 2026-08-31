# frozen_string_literal: true

require "demon/base"

module ::DiscordBot
  class Demon < ::Demon::Base
    def self.prefix
      "discord_bot"
    end

    private

    def after_fork
      stopping = false
      Signal.trap("TERM") { stopping = true }

      ::DiscordBot::Manager.activate!
      sleep 1 until stopping
    ensure
      ::DiscordBot::Manager.deactivate!
    end
  end
end
