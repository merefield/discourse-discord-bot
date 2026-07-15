# frozen_string_literal: true

# name: discourse-discord-bot
# about: Integrate Discord Bots with Discourse
# version: 0.4.0
# authors: Robert Barrow
# url: https://github.com/merefield/discourse-discord-bot

libdir = File.join(File.dirname(__FILE__), "vendor/discordrb/lib")

$LOAD_PATH.unshift(libdir) if $LOAD_PATH.exclude?(libdir)

gem "event_emitter", "0.2.6"
gem "websocket", "1.2.11"
gem "mutex_m", "0.3.0"
gem "websocket-client-simple", "0.9.0"
gem "opus-ruby", "1.0.1", { require: false }
gem "netrc", "0.11.0"
gem "mime-types-data", "3.2026.0414", require: false
gem "mime-types", "3.7.0", { require: false }
gem "domain_name", "0.6.20240107"
gem "http-cookie", "1.0.8"
gem "http-accept", "1.7.0", { require: false }
gem "rest-client", "2.1.0.rc1"

gem "discordrb-webhooks", "3.8.0", { require: false }
gem "discordrb", "3.8.0"

enabled_site_setting :discord_bot_enabled

after_initialize do
  require_relative "lib/engine"
  require_relative "lib/bot"
  require_relative "lib/manager"
  require_relative "lib/utils"
  require_relative "lib/bot_commands"
  require_relative "lib/discourse_events_handlers"
  require_relative "lib/discord_events_handlers"

  ::DiscordBot::DiscourseEventsHandlers.hook_events

  RailsMultisite::ConnectionManagement.each_connection do
    db = RailsMultisite::ConnectionManagement.current_db
    ::DiscordBot::Manager.restart(db)
  end

  on_enabled_change do
    db = RailsMultisite::ConnectionManagement.current_db
    ::DiscordBot::Manager.restart(db)
  end

  on(:site_setting_changed) do |name|
    next unless name == "discord_bot_token"

    db = RailsMultisite::ConnectionManagement.current_db
    ::DiscordBot::Manager.restart(db)
  end
end
