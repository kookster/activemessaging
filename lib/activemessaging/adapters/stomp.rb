require_gem 'stomp'
require 'stomp'

module ActiveMessaging
  module Adapters
    module Stomp

      class Connection < ::Stomp::Connection
        include ActiveMessaging::Adapter
        register :stomp

        attr_accessor :reliable

        def initialize(cfg)
          cfg[:login] ||= ""
          cfg[:passcode] ||= ""
          cfg[:host] ||= "localhost"
          cfg[:port] ||= "61613"
          cfg[:reliable] ||= FALSE
          cfg[:reconnectDelay] ||= 5
          super(cfg[:login],cfg[:passcode],cfg[:host],cfg[:port].to_i,cfg[:reliable],cfg[:reconnectDelay])
        end
      end
      
    end
  end
end