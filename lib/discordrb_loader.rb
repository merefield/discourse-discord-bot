# frozen_string_literal: true

module ::DiscordBot
  module DiscordrbLoader
    LOAD_MUTEX = Mutex.new

    module_function

    def load
      return if defined?(::Discordrb::Commands::CommandBot)

      LOAD_MUTEX.synchronize do
        return if defined?(::Discordrb::Commands::CommandBot)

        if @api_logger_initialized && ::Discordrb.const_defined?(:LOGGER, false)
          ::Discordrb.send(:remove_const, :LOGGER)
          @api_logger_initialized = false
        end

        require "discordrb"
      end
    end

    def load_api
      return if defined?(::Discordrb::API::Channel) && defined?(::Discordrb::LOGGER)

      LOAD_MUTEX.synchronize do
        return if defined?(::Discordrb::API::Channel) && defined?(::Discordrb::LOGGER)

        require "discordrb/version"
        require "discordrb/logger"
        unless ::Discordrb.const_defined?(:LOGGER, false)
          ::Discordrb.const_set(
            :LOGGER,
            ::Discordrb::Logger.new(ENV.fetch("DISCORDRB_FANCY_LOG", false)),
          )
          @api_logger_initialized = true
        end
        require "discordrb/api"
        require "discordrb/api/channel"
      end
    end
  end
end
