################################################################################
#  Copyright 2007 S. Perez. RBC Dexia Investor Servies Bank
#
#  Licensed under the Apache License, Version 2.0 (the "License");
#  you may not use this file except in compliance with the License.
#  You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
#  Unless required by applicable law or agreed to in writing, software
#  distributed under the License is distributed on an "AS IS" BASIS,
#  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#  See the License for the specific language governing permissions and
#  limitations under the License.
################################################################################

#
# WebSphere MQ adapter for activemessaging
#
require 'wmq/wmq'

module ActiveMessaging
  module Adapters
    module Adapter

      # Connection class needed by a13g
      class Connection
        include ActiveMessaging::Adapter
        register :wmq

        # Needed by a13g but never used within this adapter
        attr_accessor :reliable

        # Generic init method needed by a13g
        def initialize(cfg)
          # Set default values
          cfg[:poll_interval] ||= 0.1

          # Initialize instance members
          # Trick for the connection_options is to allow settings WMQ constants directly in broker.yml :))
          @connection_options = cfg.each_pair {|key, value| cfg[key] = instance_eval(value) if (value.instance_of?(String) && value.match("WMQ::")) }
          @queue_names = []
          @current_queue = 0
          @queues = {}
        end

        # Disconnect method needed by a13g
        # No need to disconnect from the queue manager since connection and disconnection occurs inside the send and receive methods
        # headers is never used
        def disconnect(headers = {})
        end

        # Receive method needed by a13g
        def receive
          raise "No subscription to receive messages from" if (@queue_names.nil? || @queue_names.empty?)
          start = @current_queue
          while true
            @current_queue = ((@current_queue < @queue_names.length-1) ? @current_queue + 1 : 0)
            sleep(@connection_options[:poll_interval]) if (@current_queue == start)
            q = @queues[@queue_names[@current_queue]]
            unless q.nil?
              message = retrieve_message(q)
              return message unless message.nil?
            end
          end
        end

        # Send method needed by a13g
        # headers may contains 2 different hashes to gives more control over the sending process
        #   :descriptor => {...} to populate the descriptor of the message
        #   :put_options => {...} to specify the put options for that message
        def send(q_name, message_data, headers={})
          WMQ::QueueManager.connect(@connection_options) do |qmgr|
            qmgr.open_queue(:q_name => q_name, :mode => :output) do |queue|

              message_descriptor = headers[:descriptor] || {:format => WMQ::MQFMT_STRING}
              put_options = headers[:put_options].nil? ? {} : headers[:put_options].dup

              wmq_message = WMQ::Message.new(:data => message_data, :descriptor => message_descriptor)
              queue.put(put_options.merge(:message => wmq_message, :data => nil))
              return Message.new(wmq_message, q_name)
            end
          end
        end

        # Subscribe method needed by a13g
        # headers may contains a hash to give more control over the get operation on the queue
        #   :get_options => {...} to specify the get options when receiving messages
        #   Warning : get options are set only on the first queue subscription and are common to all the queue's subscriptions
        #             Any other get options passed with subsequent subscribe on an existing queue will be discarded
        # subId is never used
        def subscribe(q_name, headers={}, subId=NIL)
          if @queues[q_name].nil?
            get_options = headers[:get_options] || {}
            q = Queue.new(q_name, get_options)
            @queues[q_name] = q
            @queue_names << q.name
          end

          q.add_subscription
        end

        # Unsubscribe method needed by a13g
        # Stop listening the queue only after the last unsubscription
        # headers is never used
        # subId is never used
        def unsubscribe(q_name, headers={}, subId=NIL)
          q = @queues[q_name]
          unless q.nil?
            q.remove_subscription
            unless q.has_subscription?
              @queues.delete(q_name)
              @queue_names.delete(q_name)
            end
          end
        end

        # called after a message is successfully received and processed
        def received message, headers={}
        end

        # called after a message is successfully received but unsuccessfully processed
        # purpose is to return the message to the destination so receiving and processing and be attempted again 
        def unreceive message, headers={}
        end

        private

        # Retrieve the first available message from the specicied queue
        # Return nil if queue is empty
        def retrieve_message(q)
          WMQ::QueueManager.connect(@connection_options) do |qmgr|
            qmgr.open_queue(:q_name => q.name, :mode => :input) do |queue|

              get_options = q.get_options.dup
              wmq_message = WMQ::Message.new
              
              if queue.get(get_options.merge(:message => wmq_message))
                return Message.new(wmq_message, q.name)
              else 
                return nil
              end
            end
          end
        end
      end

      # Message class needed by a13g (based on the same Message class in Stomp adapter)
      # Contains a reference to the MQ message object ;-) !
      class Message
        # Accessors needed by a13g
        attr_accessor :headers, :body, :command, :wmq_message
        
        def initialize(wmq_message, q_name)
          @wmq_message = wmq_message

          # Needed by a13g
          @headers = {'destination' => q_name}
          @body = wmq_message.data
          @command = 'MESSAGE'
        end

        def to_s
          "<Adapter::Message headers=#{@headers.inspect} body='#{@body}' command='#{@command}' wmq_message=#{@wmq_message}>"
        end
      end
      
      private

      # Queue class is used to keep track of the subscriptions
      # It contains :
      #   - name of the queue
      #   - options to use when getting from the queue
      #   - number of subscriptions
      class Queue
        attr_accessor :name, :get_options, :nb_subscriptions

        def initialize(name, get_options)
          @name, @get_options  = name, get_options
          @nb_subscriptions = 0
        end

        def add_subscription
          @nb_subscriptions += 1
        end
        
        def remove_subscription
          @nb_subscriptions -= 1 unless @nb_subscriptions > 0
        end

        def has_subscription?
          @nb_subscriptions > 0
        end

        def to_s
          "<Adapter::Queue name='#{@name}' get_options=#{@get_options} nb_subscriptions=#{@nb_subscriptions}>"
        end
      end
      
    end
  end
end