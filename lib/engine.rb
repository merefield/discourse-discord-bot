# frozen_string_literal: true
module ::DiscordBot
  class Engine < ::Rails::Engine
    engine_name PLUGIN_NAME
    isolate_namespace DiscordBot
  end
end
