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

        # queue_name string, headers hash
        # subscribe to listen on a queue
        def subscribe queue_name, message_headers={}
        end

        # queue_name string, headers hash
        # unsubscribe to listen on a queue
        def unsubscribe queue_name, message_headers={}
        end

        # queue_name string, body string, headers hash
        # send a single message to a queue
        def send queue_name, message_body, message_headers
        end

        # receive a single message from any of the subscribed queues
        # check each queue once, then sleep for poll_interval
        def receive
        end

        # called after a message is successfully received and processed
        # this is new, needed for Amazon SQS
        def received message
        end
        
      end

      # I recommend having a queue object to represent each subscribed queue 
      class Queue
        attr_accessor :name

        def to_s
          "<Base::Queue name='#{name}'>"
        end
      end

      # based on stomp message
      # command = MESSAGE for successful message from adapter, ERROR for problem from adapter
      # !!!! must have headers['destination'] = subscription.destination in order to match message to subscription in gateway!!!!
      class Message
        attr_accessor :headers, :body, :command
        
        def initialize headers, id, body, response, queue, command='MESSAGE'
          @headers, @body, @command =  headers, body, command
          headers['destination'] = queue.name
        end
      
        def to_s
          "<Base::Message body='#{body}' headers='#{headers.inspect}' command='#{command}' >"
        end
      end
   
    end
  end
end