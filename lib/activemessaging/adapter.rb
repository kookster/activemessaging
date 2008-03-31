module ActiveMessaging

  # include this module to make a new adapter - will register the adapter w/gateway so an be used in connection config
  module Adapter

    def self.included(included_by)
      class << included_by
        def register adapter_name
          Gateway.register_adapter adapter_name, self
        end
      end
    end

    def logger()
      @@logger = ActiveMessaging.logger unless defined?(@@logger)
      @@logger
    end

  end

end