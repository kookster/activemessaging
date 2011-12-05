require 'stomp'

require 'activemessaging/adapters/base'

module ActiveMessaging
  module Adapters
    module Stomp
      
      class Connection < ActiveMessaging::Adapters::BaseConnection
        register :stomp

        attr_accessor :stomp_connection, :retryMax, :deadLetterQueue, :configuration, :deadLetterQueuePrefix

        def initialize(cfg)
          @retryMax = cfg[:retryMax] || 0
          @deadLetterQueue = cfg[:deadLetterQueue] || nil
          @deadLetterQueuePrefix = cfg[:deadLetterQueuePrefix] || nil
        
          cfg[:login] ||= ""
          cfg[:passcode] ||= ""
          cfg[:host] ||= "localhost"
          cfg[:port] ||= "61613"
          cfg[:reliable]  = cfg[:reliable].nil? ? TRUE : cfg[:reliable]
          cfg[:reconnectDelay] ||= 5
          cfg[:clientId] ||= nil

          # hold on to the config
          @configuration = cfg

          # create a new stomp connection
          connect_headers = {}
          connect_headers['client-id'] = cfg[:clientId] if cfg[:clientId]
          @stomp_connection = ::Stomp::Connection.new(cfg[:login],cfg[:passcode],cfg[:host],cfg[:port].to_i,cfg[:reliable],cfg[:reconnectDelay], connect_headers)
        end
        
        # Checks if the connection supports dead letter queues
        def supports_dlq?
          !@deadLetterQueue.nil? || !@deadLetterQueuePrefix.nil?
        end

        # add the dead letter queue prefix to the destination
        def add_dlq_prefix(destination)
            if (ri = destination.rindex("/"))
                destination.clone.insert(ri + 1, @deadLetterQueuePrefix)
            else
                @deadLetterQueuePrefix + destination
            end

        end

        # called to cleanly get rid of connection
        def disconnect
          @stomp_connection.disconnect
        end

        # destination_name string, headers hash
        # subscribe to listen on a destination
        def subscribe destination_name, message_headers={}
          @stomp_connection.subscribe(destination_name, message_headers)
        end

        # destination_name string, headers hash
        # unsubscribe to listen on a destination
        def unsubscribe destination_name, message_headers={}
          @stomp_connection.unsubscribe(destination_name, message_headers)
        end

        # destination_name string, body string, headers hash
        # send a single message to a destination
        def send destination_name, message_body, message_headers={}
          stomp_publish(destination_name, message_body, message_headers)
        end

        # receive a single message from any of the subscribed destinations
        # check each destination once, then sleep for poll_interval
        def receive
          m = @stomp_connection.receive
          Message.new(m) if m
        end
      
        def received message, headers={}
          #check to see if the ack mode for this subscription is auto or client
          # if the ack mode is client, send an ack
          if (headers[:ack] === 'client')
            ack_headers = message.headers.has_key?(:transaction) ? { :transaction=>message.headers[:transaction]} : {}
            @stomp_connection.ack(message.headers['message-id'], ack_headers)
          end
        end
        
        # send has been deprecated in latest stomp gem (as it should be)
        def stomp_publish(destination_name="", message_body="", message_headers={})
          if @stomp_connection.respond_to?(:publish)
            @stomp_connection.publish(destination_name, message_body, message_headers)
          else
            @stomp_connection.send(destination_name, message_body, message_headers)
          end
        end

        def unreceive message, headers={}
          retry_count = message.headers['a13g-retry-count'].to_i || 0
          transaction_id = "transaction-#{message.headers['message-id']}-#{retry_count}"
          # start a transaction, send the message back to the original destination
          @stomp_connection.begin(transaction_id)
          begin

            if @retryMax > 0
              retry_headers = message.headers.stringify_keys
              retry_headers['transaction']= transaction_id
              content_type_header = retry_headers.delete('content-type')
              content_length_header = retry_headers.delete('content-length')
              # If the content-length header in the original message is nil 
              # then we need to set the :suppress_content_length option so 
              # that the stomp client does not set the content-length of the 
              # retried message. This option will allow ActiveMQ to interpret the 
              # message as a TextMessage.
              # This is somewhat of a hack because the setting of the :suppress_content_length 
              # header is usually done in the messaging.rb and is removed by the time 
              # the unreceive message is called. So I am making some assumptions here
              # on whether or not to set the option
              if content_type_header and content_type_header.include?('text/plain') && content_length_header.nil?
                  retry_headers[:suppress_content_length] = true
              end
                           
              retry_destination = retry_headers.delete('destination')
              retry_destination = headers[:destination] if headers[:destination]

              if retry_count < @retryMax
                # now send the message back to the destination
                #  set the headers for message id, priginal message id, and retry count
                retry_headers['a13g-original-message-id'] = retry_headers['message-id'] unless retry_headers.has_key?('a13g-original-message-id')
                retry_headers.delete('message-id')

                retry_headers['a13g-original-timestamp'] = retry_headers['timestamp'] unless retry_headers.has_key?('a13g-original-timestamp')
                retry_headers.delete('timestamp')

                retry_headers['a13g-retry-count'] = retry_count + 1

                # send the updated message to retry in the same transaction
                logger.warn "retrying message on #{retry_destination}"
                self.stomp_publish(retry_destination, message.body, retry_headers)

              elsif retry_count >= @retryMax && supports_dlq?
                # send the 'poison pill' message to the dead letter queue - make it persistent by default
                retry_headers['a13g-original-destination'] = retry_destination #retry_headers.delete('destination')
                retry_headers['persistent'] = true
                retry_headers.delete('message-id')
                
                # If the prefix option is set then put the prefix after the /queue/ or /topic/
                if (@deadLetterQueuePrefix)
                    dlq = add_dlq_prefix(retry_destination)
                else
                    dlq = @deadLetterQueue
                end
                logger.warn "putting message on DLQ: #{dlq}"
                self.stomp_publish(dlq, message.body, retry_headers)
              end

            end

            #check to see if the ack mode is client, and if it is, ack it in this transaction
            if (headers[:ack] === 'client')
              # ack the original message
              @stomp_connection.ack(message.headers['message-id'], message.headers.stringify_keys.merge('transaction'=>transaction_id))
            end

            # now commit the transaction
            @stomp_connection.commit transaction_id
          rescue Exception=>exc
            # if there is an error, try to abort the transaction, then raise the error
            @stomp_connection.abort transaction_id
            raise exc
          end

        end

      end
      
      class Message < ActiveMessaging::BaseMessage

        def initialize(msg)
          super(msg.body, msg.headers['message-id'], msg.headers, msg.headers['destination'])
        end

        def matches_subscription?(subscription)
          # if the subscription has been specified in the headers, rely on this
          if self.headers['subscription'] && subscription.subscribe_headers['id']
            self.headers['subscription'].to_s == subscription.subscribe_headers['id'].to_s
            
          # see if the destination uses a wildcard representation
          elsif subscription.destination.wildcard
            self.destination.to_s =~ subscription.destination.wildcard
            
          # no subscription id? no wildcard? use the name of the destination as a straight match
          else
            self.destination.to_s == subscription.destination.value.to_s
          end
        end

      end

    end
  end
end
