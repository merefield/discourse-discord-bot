# frozen_string_literal: true
# name: discourse-discord-bot
# about: Integrate Discord Bots with Discourse
# version: 0.3.31
# authors: Robert Barrow
# url: https://github.com/merefield/discourse-discord-bot


libdir = File.join(File.dirname(__FILE__), "vendor/discordrb/lib")

$LOAD_PATH.unshift(libdir) unless $LOAD_PATH.include?(libdir)

gem 'event_emitter', '0.2.6'
gem 'websocket', '1.2.11'
gem 'websocket-client-simple', '0.3.0'
gem 'opus-ruby', '1.0.1', { require: false }
gem 'netrc', '0.11.0'
gem 'mime-types-data', '3.2025.0624', require: false
gem 'mime-types', '3.7.0', { require: false }
gem 'domain_name', '0.6.20240107'
gem 'http-cookie', '1.0.8'
gem 'http-accept', '1.7.0', { require: false }
gem 'rest-client', '2.1.0.rc1'

gem 'discordrb-webhooks', '3.5.0', { require: false }
gem 'discordrb', '3.5.0'

enabled_site_setting :discord_bot_enabled

after_initialize do

  %w[
    ../lib/engine.rb
    ../lib/bot.rb
    ../lib/utils.rb
    ../lib/bot_commands.rb
    ../lib/discourse_events_handlers.rb
    ../lib/discord_events_handlers.rb
  ].each do |path|
    load File.expand_path(path, __FILE__)
  end

  def start_thread(db)
    if Discourse.running_in_rack?
      bot_thread = Thread.new do
        begin
          RailsMultisite::ConnectionManagement.establish_connection(db: db)
          ::DiscordBot::Bot.run_bot
          STDERR.puts '---------------------------------------------------'
          STDERR.puts 'Bot should now be spawned, say "Ping!" on Discord!'
          STDERR.puts '---------------------------------------------------'
          STDERR.puts '(-------      If not check logs          ---------)'
        rescue Exception => ex
          Rails.logger.error("Discord Bot: There was a problem: #{ex}")
        end
      end
    end
  end

  db_threads = {}
  RailsMultisite::ConnectionManagement.each_connection do
    next unless SiteSetting.discord_bot_enabled && ! SiteSetting.discord_bot_token.empty?
    db = RailsMultisite::ConnectionManagement.current_db
    db_threads[db] = start_thread(db)
  end

  DiscourseEvent.on(:site_setting_changed) do |name|
    if ["discord_bot_enabled", "discord_bot_token"].include? (name)
      db = RailsMultisite::ConnectionManagement.current_db
      if db_threads.has_key?(db)
        db_threads[db].kill
      end
      db_threads[db] = start_thread(db)
    end
  end
end
