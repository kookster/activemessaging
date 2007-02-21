module ActiveMessaging

  # include this module to make a new adapter - will register the adapter w/gateway so an be used in connection config
  module Adapter

    def self.included(included_by)
      class << included_by
        def register adapterName
          Gateway.register_adapter adapterName, self
        end
      end
    end

  end

end