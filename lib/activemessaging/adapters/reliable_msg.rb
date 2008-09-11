require 'reliable-msg'

module ReliableMsg

  class Client

    def queue_manager
      qm
    end

  end
end


module ActiveMessaging
  module Adapters
    module ReliableMsg

      THREAD_OLD_TXS = :a13g_reliable_msg_old_txs

      QUEUE_PARAMS = [:expires,:delivery,:priority,:max_deliveries,:drb_uri,:tx_timeout,:connect_count]
      TOPIC_PARAMS = [:expires,:drb_uri,:tx_timeout,:connect_count]

      class Connection
        include ActiveMessaging::Adapter

        register :reliable_msg

        #configurable params
        attr_accessor :reliable, :subscriptions, :destinations, :poll_interval, :current_subscription, :tx_timeout

        #generic init method needed by a13g
        def initialize cfg
          @poll_interval = cfg[:poll_interval]  || 1
          @reliable = cfg[:reliable]            || true
          @tx_timeout = cfg[:tx_timeout]        || ::ReliableMsg::Client::DEFAULT_TX_TIMEOUT

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
          get_or_create_destination(destination_name, message_headers)
          if subscriptions.has_key? destination_name
            subscriptions[destination_name].add
          else
            subscriptions[destination_name] = Subscription.new(destination_name, message_headers)
          end
        end

        # destination_name string, headers hash
        # unsubscribe to listen on a destination
        def unsubscribe destination_name, message_headers={}
          subscriptions[destination_name].remove
          subscriptions.delete(destination_name) if subscriptions[destination_name].count <= 0
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
          dest_headers = message_headers.reject {|k,v| rm_class == 'Queue' ? !QUEUE_PARAMS.include?(k) : !TOPIC_PARAMS.include?(k)}
          rm_dest = "ReliableMsg::#{rm_class}".constantize.new(dd[2], dest_headers)
          destinations[destination_name] = rm_dest
        end

        # receive a single message from any of the subscribed destinations
        # check each destination once, then sleep for poll_interval
        def receive

          raise "No subscriptions to receive messages from." if (subscriptions.nil? || subscriptions.empty?)
          start = current_subscription
          while true
            self.current_subscription = ((current_subscription < subscriptions.length-1) ? current_subscription + 1 : 0)
            sleep poll_interval if (current_subscription == start)
            destination_name = subscriptions.keys.sort[current_subscription]
            destination = destinations[destination_name]
            unless destination.nil?
              # from the way we use this, assume this is the start of a transaction, 
              # there should be no current transaction
              ctx = Thread.current[::ReliableMsg::Client::THREAD_CURRENT_TX]
              raise "There should not be an existing reliable-msg transaction. #{ctx.inspect}" if ctx

              # start a new transaction
              @tx = {:qm=>destination.queue_manager}
              @tx[:tid] = @tx[:qm].begin @tx_timeout
              Thread.current[::ReliableMsg::Client::THREAD_CURRENT_TX] = @tx
              begin

                # now call a get on the destination - it will use the transaction
                #the commit or the abort will occur in the received or unreceive methods
                reliable_msg = destination.get subscriptions[destination_name].headers[:selector]
                @tx[:qm].commit(@tx[:tid]) if reliable_msg.nil?

              rescue Object=>err
                #abort the transaction on error
                @tx[:qm].abort(@tx[:tid])

                raise err unless reliable
                puts "receive failed, will retry in #{@poll_interval} seconds"
                sleep poll_interval
              end
              return Message.new(reliable_msg.id, reliable_msg.object, reliable_msg.headers, destination_name, 'MESSAGE', @tx) if reliable_msg
              
              Thread.current[::ReliableMsg::Client::THREAD_CURRENT_TX] = nil
            end
          end
        end

        # called after a message is successfully received and processed
        def received message, headers={}
          begin
            message.transaction[:qm].commit(message.transaction[:tid]) 
          rescue Object=>ex
            puts "received failed: #{ex.message}"
          ensure
            Thread.current[::ReliableMsg::Client::THREAD_CURRENT_TX] = nil
          end
          
        end
        
        # called after a message is successfully received and processed
        def unreceive message, headers={}
          begin
            message.transaction[:qm].abort(message.transaction[:tid])
          rescue Object=>ex
            puts "unreceive failed: #{ex.message}"
          ensure
            Thread.current[::ReliableMsg::Client::THREAD_CURRENT_TX] = nil
          end
        end

      end
      
      class Subscription
        attr_accessor :name, :headers, :count
        
        def initialize(destination, headers={}, count=1)
          @destination, @headers, @count = destination, headers, count
        end
        
        def add
          @count += 1
        end

        def remove
          @count -= 1
        end

      end

      class Message
        attr_accessor :id, :body, :headers, :command, :transaction
        
        def initialize id, body, headers, destination_name, command='MESSAGE', transaction=nil
          @id, @body, @headers, @command, @transaction =  id, body, headers, command, transaction
          headers['destination'] = destination_name
        end
      
        def to_s
          "<ReliableMessaging::Message id='#{id}' body='#{body}' headers='#{headers.inspect}' command='#{command}' >"
        end
      end
   
    end
  end
end