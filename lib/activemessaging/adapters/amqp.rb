require 'activemessaging/adapters/base'

require 'carrot'
require 'digest/md5'
require 'bert'

# make sure ActiveMessaging::Processor is already loaded so we actually override it!
require 'activemessaging/processor'

module ActiveMessaging
  class Processor
    def self.subscribes_to destination_name, headers={}
      # let's default to using the same exchange_type/exchange_name as defined in the messages.rb
      # for the given destination. XXX: THIS IS A BIG TIME MONKEY PATCH! Might consider pushing a
      # proper patch upstream instead of jury-rigging this.
      d = ActiveMessaging::Gateway.find_destination(destination_name)
      type, name = [ d.publish_headers[:exchange_type], d.publish_headers[:exchange_name] ]
      ActiveMessaging::Gateway.subscribe_to destination_name, self, { :exchange_type => type, :exchange_name => name }.merge(headers)
    end
  end

  module Adapters
    module Amqp
      class Connection
        include ActiveMessaging::Adapter
        register :amqp

        class InvalidExchangeType < ArgumentError; end
        
        @@mutex = Mutex.new
        
        def initialize config = {}
          @connect_options = {
            :user  => config[:user]  || 'guest',
            :pass  => config[:pass]  || 'guest',
            :host  => config[:host]  || 'localhost',
            :port  => config[:port]  || 5672,
            :vhost => config[:vhost] || nil,
            :ssl   => config[:ssl]   || false,
            :ssl_verify => config[:ssl_verify] || OpenSSL::SSL::VERIFY_PEER,
          }
          
          @debug = config[:debug].to_i rescue 0
          
          @auto_generated_queue = false
          unless config[:queue_name]
            @queue_name = Digest::MD5.hexdigest Time.now.to_s
            @auto_generated_queue = true
          else
            @queue_name = config[:queue_name]
          end

          @queue_config = {
            :durable     => @auto_generated_queue ? false : config[:queue_durability] || true,
            :auto_delete => @auto_generated_queue ? true : config[:queue_auto_delete] || false,
            :exclusive   => @auto_generated_queue ? true : config[:queue_exclusive]   || true
          }
        end
        
        def received message, headers = {}
          puts "Received Message - ACK'ing with delivery_tag '#{message.headers[:delivery_tag]}'" if @debug > 0
          client.server.send_frame(::Carrot::AMQP::Protocol::Basic::Ack.new(:delivery_tag => message.headers[:delivery_tag]))
        end
        
        def unreceive message, headers = {}
          puts "Un-Receiving Message - REJECTing with delivery_tag '#{message.headers[:delivery_tag]}'" if @debug > 0
          client.server.send_frame(::Carrot::AMQP::Protocol::Basic::Reject.new(:delivery_tag => message.headers[:delivery_tag]))
        end
        
        def receive
          while true 
            message = queue.pop(:ack => true)
            unless message.nil?
              message = AmqpMessage.decode(message) unless message.nil?
              message.headers[:delivery_tag] = queue.delivery_tag
              puts "RECEIVE: #{message.inspect}" if @debug 
              return message
            end
            sleep 0.2
          end
        end
        
        def send queue_name, body, headers = {}
          headers[:routing_key] ||= queue_name
          message = AmqpMessage.new({:headers => headers, :body => body}, queue_name)
          if @debug > 0
            puts "Sending the following message: "; pp message
          end
          exchange(*exchange_info(headers)).publish(message.encode, :key => headers[:routing_key])
        end
        
        def subscribe queue_name, headers = {}, subId = nil
          if @debug > 1
            puts "Begin Subscribe Request:"
            puts "    Queue Name: #{queue_name.inspect}"
            puts "       Headers: #{headers.inspect}"
            puts "         subId: #{subId.inspect}"
            puts "     EXCH INFO: #{exchange_info(headers).inspect}"
            puts "End Subscribe Request."
          end
          
          routing_key = headers[:routing_key] || queue_name
          queue.bind(exchange(*exchange_info(headers)), :key => routing_key)
        end
        
        def unsubscribe(queue_name, headers={}, subId=nil)
          if @debug > 1
            puts "Begin UNsubscribe Request:"
            puts "    Queue Name: #{queue_name.inspect}"
            puts "    Headers:    #{headers.inspect}"
            puts "    subId:      #{subId.inspect}"
            puts "End UNsubscribe Request."
          end
          
          routing_key = headers[:routing_key] || queue_name
          queue.unbind(exchange(*exchange_info(headers)), :key => routing_key)
        end
        
        def disconnect(headers={})
          @client.stop
        end
        
        private

        def exchange_info headers
          [ (headers[:exchange_type].to_sym rescue nil) || :direct, headers[:exchange_name] || nil]
        end
        
        def exchange type, name, *args
          type = type.to_sym rescue nil
          unless [:topic, :fanout, :direct].include? type
            raise InvalidExchangeType, "The carrot library does not support an exchange type of '#{type.inspect}'"
          end

          name ||= "amq.#{type}"
          puts "Exchange [#{type}::#{name}]: #{args.inspect}" if @debug > 3
          (@exchanges||={})[name] ||= ::Carrot::AMQP::Exchange.new client, type, name, *args
        end

        def queue
          return @queue unless @queue.nil?
          puts "Queue [#{@queue_name}]: #{@queue_config.inspect}" if @debug > 0
          @queue ||= client.queue(@queue_name, @queue_config)
        end
        
        def client
          return @client unless @client.nil?
          puts "Client [amqp]: #{@connect_options.inspect}" if @debug > 0
          @client ||= Carrot.new(@connect_options)
        end

      end
      
      class AmqpMessage
        attr_reader :command
        
        def initialize(data, queue_name = nil)
          @data = {
            :body    => data[:body] || {},
            :headers => data[:headers] || {}
          }
          
          headers['destination'] ||= queue_name || headers[:routing_key]
          @command = "MESSAGE"
        end
        
        def body
          @data[:body]
        end
        
        def headers
          @data[:headers]
        end
        
        def encode
          BERT.encode @data
        end
        
        def self.decode data
          AmqpMessage.new BERT.decode(data)
        end
      end
    end
  end
end


