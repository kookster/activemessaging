
if defined?(JRUBY_VERSION)
#require 'java'
include Java

import javax.naming.InitialContext
import javax.jms.MessageListener

module ActiveMessaging
  module Adapters
    module Jms
    
      class Connection
        include ActiveMessaging::Adapter
        register :jms
        
        attr_accessor :reliable, :connection, :session, :producers, :consumers
        
        def initialize cfg={}
          @url = cfg[:url]
          @login = cfg[:login]
          @passcode = cfg[:passcode]
          #initialize our connection factory
          if cfg.has_key? :connection_factory
            #this initialize is probably activemq specific. There might be a more generic
            #way of getting this without resorting to jndi lookup.
            eval <<-end_eval
              @connection_factory = Java::#{cfg[:connection_factory]}.new(@login, @password, @url)
            end_eval
          elsif cfg.has_key? :jndi
            @connection_factory = javax.naming.InitialContext.new().lookup(cfg[:jndi])
          else
            raise "Either jndi or connection_factory has to be set in the config."
          end
          raise "Connection factory could not be initialized." if @connection_factory.nil?
          
          @connection = @connection_factory.create_connection()
          @session = @connection.createSession(false, 1)
          @destinations = []
          @producers = {}
          @consumers = {}
          @connection.start
        end
        
        def subscribe queue_name, headers={}
          queue_name = check_destination_type queue_name, headers
          find_or_create_consumer queue_name, headers
        end
        
        def unsubscribe queue_name, headers={}
          queue_name = check_destination_type queue_name, headers
          consumer = @consumers[queue_name]
          unless consumer.nil?
            consumer.close
            @consumers.delete queue_name
          end
        end
        
        def send queue_name, body, headers={}
          queue_name = check_destination_type queue_name, headers
          producer = find_or_create_producer queue_name, headers.symbolize_keys
          message = @session.create_text_message body
          headers.stringify_keys.each do |key, value|
            if ['id', 'message-id', 'JMSMessageID'].include? key
              message.setJMSMessageID value.to_s
            elsif ['correlation-id', 'JMSCorrelationID'].include? key
              message.setJMSCorrelationID value.to_s
            elsif ['expires', 'JMSExpiration'].include? key
              message.setJMSExpiration value.to_i
            elsif ['persistent', 'JMSDeliveryMode'].include? key
              message.setJMSDeliveryMode(value ? 2 : 1)
            elsif ['priority', 'JMSPriority'].include? key
              message.setJMSPriority value.to_i
            elsif ['reply-to', 'JMSReplyTo'].include? key
              message.setJMSReplyTo value.to_s
            elsif ['type', 'JMSType'].include? key
              message.setJMSType value.to_s
            else #is this the most appropriate thing to do here?
              message.set_string_property key, value.to_s
            end
          end
          producer.send message
        end
        
        def receive_any
          @consumers.find do |k, c|
            message = c.receive(1)
            return condition_message(message) unless message.nil?
          end
        end
        
        def receive queue_name=nil, headers={}
          if queue_name.nil?
            receive_any
          else
            consumer = subscribe queue_name, headers
            message = consumer.receive(1)
            unsubscribe queue_name, headers
            condition_message message
          end
        end
        
        def received message, headers={}
          #do nothing
        end
        
        def unreceive message, headers={}
          # do nothing
        end

        def close
          @consumers.each {|k, c| c.stop }
          @connection.stop
          @session.close
          @connection.close
          @connection = nil
          @session = nil
          @consumers = {}
          @producers = {}
        end
        
        def find_or_create_producer queue_name, headers={}
          producer = @producers[queue_name]
          if producer.nil?
            destination = find_or_create_destination queue_name, headers
            producer = @session.create_producer destination
          end
          producer
        end
        
        def find_or_create_consumer queue_name, headers={}
          consumer = @consumers[queue_name]
          if consumer.nil?
            destination = find_or_create_destination queue_name, headers
            if headers.symbolize_keys.has_key? :selector
              consumer = @session.create_consumer destination, headers.symbolize_keys[:selector]
            else
              consumer = @session.create_consumer destination
            end
            
            @consumers[queue_name] = consumer
          end
          consumer
        end
        
        def find_or_create_destination queue_name, headers={}
          destination = find_destination queue_name, headers[:destination_type]
          if destination.nil?
            if headers.symbolize_keys[:destination_type] == :topic
              destination = @session.create_topic(queue_name.to_s)
              @destinations << destination
            elsif headers.symbolize_keys[:destination_type] == :queue
              destination = @session.create_queue(queue_name.to_s)
              @destinations << destination
            else
              raise "headers[:destination_type] must be either :queue or :topic.  was #{headers[:destination_type]}"
            end
          end
          destination
        end
        
        protected
        
        def condition_message message
          message.class.class_eval { 
            alias_method :body, :text unless method_defined? :body
            
            def command
              "MESSAGE"
            end
            
            def headers
              destination.to_s =~ %r{(queue|topic)://(.*)}
              puts "/#{$1}/#{$2}"
              {'destination' => "/#{$1}/#{$2}"}
            end
            
          } unless message.nil? || message.respond_to?(:command)
          message
        end
        
        def check_destination_type queue_name, headers
          stringy_h = headers.stringify_keys
          if queue_name =~ %r{^/(topic|queue)/(.*)$}  && !stringy_h.has_key?('destination_type')
            headers['destination_type'] = $1.to_sym
            return $2
          else
            raise "Must specify destination type either with either 'headers[\'destination_type\']=[:queue|:topic]' or /[topic|queue]/destination_name for queue name '#{queue_name}'" unless [:topic, :queue].include? stringy_h['destination_type']
          end
        end
        
        def find_destination queue_name, type
          @destinations.find do |d| 
            if d.is_a?(javax.jms.Topic) && type == :topic
              d.topic_name == queue_name
            elsif d.is_a?(javax.jms.Queue) && type == :queue
              d.queue_name == queue_name
            end
          end
        end
      end
#      
#      class RubyMessageListener
#         include javax.jms.MessageListener
# 
#         def initialize(connection, destination, name)
#           @connection = connection
#           @destination = destination
#           @name = name
#         end
# 
#         def onMessage(msg)
#           headers = {}
#           enm = msg.getPropertyNames
#           while enm.hasMoreElements
#             key = enm.nextElement
#             headers[key.to_s] = msg.getStringProperty(key)
#           end
#           Gateway.dispatch(JMSRecvMessage.new(headers,msg.text,@name))
#         rescue => e
#           STDERR.puts "something went really wrong with a message: #{e.inspect}"
#        end
#      end
#      
#      class JMSRecvMessage < ActiveMessaging::Adapters::Base::Message
#         def initialize(headers, body, name, command='MESSAGE')
#           @headers = headers
#           @body = body
#           @command =  command
#           @headers['destination'] = name
#         end
#       end
    end
  end
end

end