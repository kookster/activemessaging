require 'reliable-msg'

module ActiveMessaging
  module Adapters
    module ReliableMsg

      class Connection
        include ActiveMessaging::Adapter

        register :reliable_msg

        #configurable params
        attr_accessor :reliable, :subscriptions, :destinations, :poll_interval, :current_subscription

        #generic init method needed by a13g
        def initialize cfg
          @poll_interval = cfg[:poll_interval] || 1
          @reliable = cfg[:reliable]           || true

          @subscriptions = {}
          @destinations = {}
          @current_subscription = 0
        end

        # called to cleanly get rid of connection
        def disconnect
          nil
        end

        # destination_name string, headers hash
        # subscribe to listen on a destination
        # use '/destination-type/name' convetion, like stomp
        def subscribe destination_name, message_headers={}
          get_or_create_destination(destination_name)
          if subscriptions.has_key? destination_name
            subscriptions[destination_name] += 1
          else
            subscriptions[destination_name] = 1
          end
        end

        # destination_name string, headers hash
        # unsubscribe to listen on a destination
        def unsubscribe destination_name, message_headers={}
          subscriptions[destination_name] -= 1
          subscriptions.delete(destination_name) if subscriptions[destination_name] <= 0
        end

        # destination_name string, body string, headers hash
        # send a single message to a destination
        def send destination_name, message_body, message_headers={}
          dest = get_or_create_destination(destination_name)
          begin
            dest.put message_body, message_headers
          rescue Object=>err
            raise err unless reliable
            puts "send failed, will retry in #{@poll_interval} seconds"
            sleep @poll_interval
          end
        end
        
        def get_or_create_destination destination_name, message_headers={}
          return destinations[destination_name] if destinations.has_key? destination_name
          dd = /^\/(queue|topic)\/(.*)$/.match(destination_name)
          rm_class = dd[1].titleize
          message_headers.delete("id")
          rm_dest = "ReliableMsg::#{rm_class}".constantize.new(dd[2], message_headers)
          destinations[destination_name] = rm_dest
        end

        # receive a single message from any of the subscribed destinations
        # check each destination once, then sleep for poll_interval
        def receive
          raise "No subscriptions to receive messages from." if (subscriptions.nil? || subscriptions.empty?)
          start = @current_subscription
          message = nil
          while true
            current_subscription = ((@current_subscription < subscriptions.length-1) ? @current_subscription + 1 : 0)
            sleep poll_interval if (@current_subscription == start)
            destination_name = subscriptions.keys.sort[@current_subscription]
            destination = destinations[destination_name]
            unless destination.nil?
              begin
                reliable_msg = destination.get
              rescue Object=>err
                raise err unless reliable
                puts "receive failed, will retry in #{@poll_interval} seconds"
                sleep @poll_interval
              end
              message = Message.new reliable_msg.id, reliable_msg.object, reliable_msg.headers, destination_name unless reliable_msg.nil?
              return message
            end
          end
        end

        # called after a message is successfully received and processed
        def received message, headers={}
          nil
        end
        
      end

      class Message
        attr_accessor :id, :body, :headers, :command
        
        def initialize id, body, headers, destination_name, command='MESSAGE'
          @id, @body, @headers, @command =  id, body, headers, command
          headers['destination'] = destination_name
        end
      
        def to_s
          "<ReliableMessaging::Message id='#{id}' body='#{body}' headers='#{headers.inspect}' command='#{command}' >"
        end
      end
   
    end
  end
end