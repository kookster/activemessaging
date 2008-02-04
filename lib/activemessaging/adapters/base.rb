module ActiveMessaging
  module Adapters
    module Base


      # use this as a base for implementing new connections
      class Connection
        include ActiveMessaging::Adapter

        #use the register method to add the adapter to the configurable list of supported adapters
        # register :generic

        #configurable params
        attr_accessor :reliable

        #generic init method needed by a13g
        def initialize cfg
        end

        # called to cleanly get rid of connection
        def disconnect
        end

        # destination_name string, headers hash
        # subscribe to listen on a destination
        def subscribe destination_name, message_headers={}
        end

        # destination_name string, headers hash
        # unsubscribe to listen on a destination
        def unsubscribe destination_name, message_headers={}
        end

        # destination_name string, body string, headers hash
        # send a single message to a destination
        def send destination_name, message_body, message_headers={}
        end

        # receive a single message from any of the subscribed destinations
        # check each destination once, then sleep for poll_interval
        def receive
        end

        # called after a message is successfully received and processed
        def received message, headers={}
        end

        # called after a message is successfully received but unsuccessfully processed
        # purpose is to return the message to the destination so receiving and processing and be attempted again 
        def unreceive message, headers={}
        end
        
      end

      # I recommend having a destination object to represent each subscribed destination 
      class Destination
        attr_accessor :name

        def to_s
          "<Base::Destination name='#{name}'>"
        end
      end

      # based on stomp message
      # command = MESSAGE for successful message from adapter, ERROR for problem from adapter
      # !!!! must have headers['destination'] = subscription.destination in order to match message to subscription in gateway!!!!
      class Message
        attr_accessor :headers, :body, :command
        
        def initialize headers, id, body, response, destination, command='MESSAGE'
          @headers, @body, @command =  headers, body, command
          headers['destination'] = destination.name
        end
      
        def to_s
          "<Base::Message body='#{body}' headers='#{headers.inspect}' command='#{command}' >"
        end
      end
   
    end
  end
end