gem 'stomp'
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
          cfg[:reliable] ||= TRUE
          cfg[:reconnectDelay] ||= 5
          super(cfg[:login],cfg[:passcode],cfg[:host],cfg[:port].to_i,cfg[:reliable],cfg[:reconnectDelay])
        end
        
        def received message, headers={}
          #check to see if the ack mode for this subscription is auto or client
          # if the ack mode is client, send an ack
          if (headers[:ack] === 'client')
            ack_headers = message.headers.has_key?(:transaction) ? message.headers[:transaction] : {}
            ack message.headers['message-id'], ack_headers
          end
        end
      end
      
    end
  end
end