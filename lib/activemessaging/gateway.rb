require 'yaml'

module ActiveMessaging
  
  def ActiveMessaging.logger
    @@logger = ActiveRecord::Base.logger unless defined?(@@logger)
    @@logger = Logger.new(STDOUT) unless defined?(@logger)
    @@logger
  end

  def ActiveMessaging.connection(configuration={})
    @@connection = Gateway.adapters[configuration[:adapter]].new(configuration) unless defined?(@@connection)
    @@connection
  end

  def ActiveMessaging.disconnect
    begin
      unless @@connection.nil?
        temp_reliable = @@connection.reliable
        @@connection.reliable = false
        Gateway.unsubscribe
        @@connection.disconnect 
      end
    rescue
      puts "=> Error on disconnect: #{$!.message}"
      raise $!
    ensure
      @@connection.reliable = temp_reliable unless !defined?(@@connection) || @@connection.nil?
    end
  end
  
  class Gateway
    cattr_accessor :adapters, :subscriptions, :named_queues, :filters, :connection_configuration, :processor_groups
    @@adapters = {}
    @@subscriptions = []
    @@named_queues = {}
    @@filters = []
    @@connection_configuration = {}
    @@processor_groups = {}

    @@trace_on = nil
    @@current_processor_group = nil
 
    class <<self
      
      def register_adapter adapter_name, adapter_class
        adapters[adapter_name] = adapter_class
      end
      
      def filter filter, options = {}
        filters << filter
      end
      
      def subscribe
        subscriptions.each do |subscription|
          subscription.subscribe(ActiveMessaging.connection(connection_configuration))
        end
      end

      def unsubscribe
        subscriptions.each do |subscription|
          subscription.unsubscribe(ActiveMessaging.connection(connection_configuration))
        end
      end

      def disconnect
        ActiveMessaging.disconnect
      end

      def dispatch_next
        dispatch(ActiveMessaging.connection(connection_configuration).receive)
      end
      
      def execute_filter_chain(direction, message, details={})
        filters.each do |filter|
          continue = callcc do |cont|
            filter.process(message, details){|| cont.call(true)}
            # if the filter doesn't yield we shouldn't continue the processing of the message
            cont.call(false)
          end
          return unless continue
        end
        yield(message)
      end

      def prepare_application
        puts "Calling verify_active_connections!"
        ActiveRecord::Base.verify_active_connections!
        puts "Called verify_active_connections"
      end

      def dispatch(message)
        prepare_application
        case message.command
          when 'ERROR' 
            ActiveMessaging.logger.error('Error from messaging infrastructure: ' + message.headers['message'])
          when 'MESSAGE'
            sent = false
            subscriptions.each do |subscription| 
              if subscription.matches?(message) then
                routing = {
                  :receiver=>subscription.processor_class, 
                  :queue=>subscription.queue,
                  :direction => :incoming
                }
                execute_filter_chain(:in, message, routing) do |m| 
                  subscription.processor_class.new.process!(m)
                end
                sent = true
              end
            end          
            ActiveMessaging.logger.error('No-one responded to ' + message) unless sent
          else 
            ActiveMessaging.logger.error('Unknown message command: ' + message.inspect)
        end
      end

      def define
        #load the yaml broker file to get connection_configuration
        load_connection_configuration

        #run the rest of messaging.rb
        yield self
      end
      
      def queue queue_name, queue, publish_headers={}
        named_queues[queue_name] = Queue.new queue_name, queue, publish_headers
      end
      
      def find_queue queue_name
        real_queue = named_queues[queue_name]
        raise "You have not yet defined a queue named #{queue_name}. Queues currently defined are [#{named_queues.keys.join(',')}]" if real_queue.nil?
        real_queue
      end

      def trace_on queue
        @@trace_on = queue
      end

      def subscribe_to queue_name, processor, headers={}
        proc_sym = processor.name.underscore.to_sym
        if (!current_processor_group || processor_groups[current_processor_group].include?(proc_sym))
          subscriptions << Subscription.new(find_queue(queue_name), processor, headers)
        end
      end

      def publish queue_name, body, publisher=nil, headers = {}
        real_queue = find_queue(queue_name)
        details = {
          :publisher => publisher, 
          :queue => real_queue,
          :direction => :outgoing
        }
        message = OpenStruct.new(:body => body, :headers => headers.reverse_merge(real_queue.publish_headers))
        execute_filter_chain(:out, message, details) do |message|
          ActiveMessaging.connection(connection_configuration).send real_queue.destination, message.body, message.headers
        end
      end

      def processor_group group_name, *processors        
        if processor_groups.has_key? group_name
          processor_groups[group_name] =  processor_groups[group_name] + processors
        else
          processor_groups[group_name] = processors
        end
      end

      def current_processor_group
        if ARGV.length > 0 && !@@current_processor_group
          ARGV.each {|arg|
            pair = arg.split('=')
            if pair[0] == 'process-group'
              group_sym = pair[1].to_sym
              if processor_groups.has_key? group_sym
                @@current_processor_group = group_sym
              else
                puts "Unrecognized process-group."
                puts "You specified process-group #{pair[1]}, make sure this is specified in config/messaging.rb"
                puts "  ActiveMessaging::Gateway.define do |s|"
                puts "  s.processor_groups = { :group1 => [:foo_bar1_processor], :group2 => [:foo_bar2_processor] }"
                puts "  end"
                exit
              end
            end
          }
        end
        @@current_processor_group
      end
      
      def load_connection_configuration
        broker_config = YAML.load_file(File.join(RAILS_ROOT, 'config', 'broker.yml'))
        config = broker_config[RAILS_ENV].symbolize_keys
        config[:adapter] = config[:adapter].to_sym if config[:adapter]
        config[:adapter] ||= :stomp
        @@connection_configuration = config
      end
      
    end

  end
  
  class Subscription
    attr_accessor :queue, :processor_class, :subscribe_headers
        
    def initialize(queue, processor_class, subscribe_headers = {})
      @queue, @processor_class, @subscribe_headers = queue, processor_class, subscribe_headers
      subscribe_headers['id'] = processor_class.name.underscore unless subscribe_headers.key? 'id'
    end
    
    def matches?(message)
      message.headers['destination'].to_s == queue.destination.to_s
    end
    
    def subscribe(connection)
      puts "=> Subscribing to #{queue.destination} (processed by #{processor_class})"
      connection.subscribe(queue.destination, subscribe_headers) 
    end

    def unsubscribe(connection)
      puts "=> Unsubscribing from #{queue.destination} (processed by #{processor_class})"
      connection.unsubscribe(queue.destination, subscribe_headers)
    end
  end
  
  class Queue
    DEFAULT_PUBLISH_HEADERS = { :persistent=>true }

    attr_accessor :name, :destination, :publish_headers

    def initialize(name, destination, publish_headers = {})
      @name, @destination, @publish_headers = name, destination, publish_headers
      @publish_headers.reverse_merge! DEFAULT_PUBLISH_HEADERS
    end
  end

end #module
