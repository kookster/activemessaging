
module ActiveMessaging
  module Adapters
    module Test
    
      class Connection
        include ActiveMessaging::Adapter
        register :test
        
        attr_accessor :config
        
        def initialize cfg
          @config = cfg
          @subscriptions = []
          @queues = []
        end
        
        def disconnect
          @subscriptions = []
          @queues = []
        end
        
        def subscribe queue_name, subscribe_headers={}
          open_queue queue_name
          unless @subscriptions.find {|s| s.name == queue_name} 
            @subscriptions << Subscription.new(queue_name, subscribe_headers)
          end
        end
        
        def unsubscribe queue_name, unsubscribe_headers={}
          @subscriptions.delete_if {|s| s.name == queue_name}
        end
        
        def send queue_name, message_body, message_headers={}
          open_queue queue_name
          queue = find_queue queue_name
          queue.send Message.new(message_headers, nil, message_body, nil, queue)
        end
        
        def receive
          queue = @queues.find do |q|
            find_subscription(q.name) && !q.empty?
          end
          queue.receive unless queue.nil?
        end
        
        def received message
          #do nothing
        end
        
        #test helper methods
        def find_message queue_name, body
          all_messages.find do |m|
            m.headers['destination'] == queue_name && m.body = body
          end
        end
        
        def open_queue queue_name
          unless find_queue queue_name
            @queues << Queue.new(queue_name)
          end
        end
        
        def find_queue queue_name
          @queues.find{|q| q.name = queue_name }
        end
        
        def find_subscription queue_name
          @subscriptions.find{|s| s.name == queue_name}
        end
        
        def all_messages
          @queues.map {|q| q.messages }.flatten
        end
      end
      
      class Queue < ActiveMessaging::Adapters::Base::Queue
        
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
      
      end
      
      class Subscription
        attr_accessor :name, :headers
        
        def initialize name, headers
          @name = name
          @headers = headers
        end
        
        def to_s
          "<Test::Subscription queue='#{name}' headers='#{headers.inspect}' >"
        end
      end
      
      class Message < ActiveMessaging::Adapters::Base::Message
      end
    end
  end
end