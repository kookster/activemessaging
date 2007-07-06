
module ActiveMessaging
  module Adapters
    module Test
    
      class Connection
        include ActiveMessaging::Adapter
        register :test
        
        attr_accessor :config, :subscriptions, :destinations, :connected, :received_messages
        
        def initialize cfg
          @config = cfg
          @subscriptions = []
          @destinations = []
          @received_messages = []
          @connected = true
        end
        
        def disconnect
          @subscriptions = []
          @destinations = []
          @received_messages = []
          @connected = false
        end
        
        def subscribe destination_name, subscribe_headers={}
          open_destination destination_name
          unless @subscriptions.find {|s| s.name == destination_name} 
            @subscriptions << Subscription.new(destination_name, subscribe_headers)
          end
          @subscriptions.last
        end
        
        def unsubscribe destination_name, unsubscribe_headers={}
          @subscriptions.delete_if {|s| s.name == destination_name}
        end
        
        def send destination_name, message_body, message_headers={}
          open_destination destination_name
          destination = find_destination destination_name
          destination.send Message.new(message_headers, nil, message_body, nil, destination)
        end
        
        def receive
          destination = @destinations.find do |q|
            find_subscription(q.name) && !q.empty?
          end
          destination.receive unless destination.nil?
        end
        
        # should not be 2 defs for receive, this isn't java, ya know? -Andrew
        # def receive destination_name, headers={}
        #   subscribe destination_name, headers
        #   destination = find_destination destination_name
        #   message = destination.receive
        #   unsubscribe destination_name, headers
        #   message
        # end
        
        def received message, headers={}
          @received_messages << message
        end
        
        #test helper methods
        def find_message destination_name, body
          all_messages.find do |m|
            m.headers['destination'] == destination_name && m.body.to_s == body.to_s
          end
        end
        
        def open_destination destination_name
          unless find_destination destination_name
            @destinations << Destination.new(destination_name)
          end
        end
        
        def find_destination destination_name
          @destinations.find{|q| q.name == destination_name }
        end
        
        def find_subscription destination_name
          @subscriptions.find{|s| s.name == destination_name}
        end
        
        def all_messages
          @destinations.map {|q| q.messages }.flatten
        end
      end
      
      class Destination
        
        attr_accessor :name, :messages
        
        def initialize name
          @name = name
          @messages = []
        end
        
        def receive
          @messages.shift
        end

        def send message
          @messages << message
        end
        
        def empty?
          @messages.empty?
        end
        
        def to_s
          "<Test::Destination name='#{name}' messages='#{@messages.inspect}'>"
        end
      end
      
      class Subscription
        attr_accessor :name, :headers
        
        def initialize name, headers
          @name = name
          @headers = headers
        end
        
        def to_s
          "<Test::Subscription destination='#{name}' headers='#{headers.inspect}' >"
        end
      end
      
      class Message
        attr_accessor :headers, :body, :command
        
        def initialize headers, id, body, response, destination, command='MESSAGE'
          @headers, @body, @command =  headers, body, command
          headers['destination'] = destination.name
        end
      
        def to_s
          "<Test::Message body='#{body}' headers='#{headers.inspect}' command='#{command}' >"
        end
      end
    end
  end
end