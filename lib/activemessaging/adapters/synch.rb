# 
# This is meant to avoid the need to use a broker in development, and generally make development mode easier
# 
module ActiveMessaging
  module Adapters
    module Synch
    
      class Connection  < ActiveMessaging::Adapters::BaseConnection
        register :synch

        #configurable params
        attr_accessor :configuration

        #generic init method needed by a13g
        def initialize cfg
          @configuration = cfg
        end

        def send destination_name, message_body, message_headers={}
          message = Message.new(message_body, 'id', message_headers, destination_name, 'MESSAGE')
          pid = fork {
            ActiveMessaging.logger.debug "\n-------------------- ActiveMessaging synch before dispath --------------------"
            ActiveMessaging::Gateway.dispatch(message)
            ActiveMessaging.logger.debug "-------------------- ActiveMessaging synch after dispath --------------------\n"
          }
          Process.waitpid(pid)

          # I needed this using mysql2, not exactly sure why the conn gets banged up by the fork, but doesn't hurt much
          ActiveRecord::Base.verify_active_connections!
        end

      end

      class Message < ActiveMessaging::BaseMessage
        attr_accessor :command

        def initialize body, id, headers, destination, command='MESSAGE'
          # ActiveMessaging.logger.debug "Message headers:#{headers.inspect}, id:#{id}, body:#{body}, destination:#{destination}, command:#{command}"
          @headers, @body, @destination, @command =  headers, body, destination, command
          headers['destination'] = destination
        end

      end
    
    end
  end
end
