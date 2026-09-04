# frozen_string_literal: true

# name: discourse-discord-bot
# about: Integrate Discord Bots with Discourse
# version: 0.5.0
# authors: Robert Barrow
# url: https://github.com/merefield/discourse-discord-bot

libdir = File.join(File.dirname(__FILE__), "vendor/discordrb/lib")

$LOAD_PATH.unshift(libdir) if $LOAD_PATH.exclude?(libdir)

gem "event_emitter", "0.2.6", { require: false }
gem "websocket", "1.2.11", { require: false }
gem "mutex_m", "0.3.0", { require: false }
gem "websocket-client-simple", "0.9.0", { require: false }
gem "opus-ruby", "1.0.1", { require: false }
gem "netrc", "0.11.0", { require: false }
gem "mime-types", "3.7.0", { require: false }
gem "domain_name", "0.6.20240107", { require: false }
gem "http-cookie", "1.0.8", { require: false }
gem "http-accept", "1.7.0", { require: false }
gem "rest-client", "2.1.0.rc1", { require: false }

gem "discordrb-webhooks", "3.8.0", { require: false }
gem "discordrb", "3.8.0", { require: false }

module ::DiscordBot
  PLUGIN_NAME = "discourse-discord-bot"
end

Rails.autoloaders.main.push_dir(File.join(__dir__, "lib"), namespace: ::DiscordBot)

enabled_site_setting :discord_bot_enabled

require_relative "lib/engine"
require_relative "lib/demon"
register_demon_process ::DiscordBot::Demon

after_initialize do
  ::DiscordBot::DiscourseEventsHandlers.hook_events

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
