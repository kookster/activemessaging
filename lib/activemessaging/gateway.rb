module ActiveMessaging

  def ActiveMessaging.logger
    @@logger = ActiveRecord::Base.logger unless defined?(@@logger)
    unless defined?(@logger)
      @@logger = Logger.new(STDOUT) 
    end
    @@logger
  end

  def ActiveMessaging.connection(configuration={})
    @@connection = ActiveMessaging::Adapters::Stomp::Connection.new(configuration) unless defined?(@@connection)
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
    cattr_accessor :subscriptions, :named_queues, :filters, :connection_configuration, :processor_groups
    @@filters = []
    @@subscriptions = []
    @@named_queues = {}
    @@trace_on = nil
    @@connection_configuration = {}
    @@processor_groups = {}
    @@current_processor_group = nil
 
    class <<self
      
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

      def dispatch(message)
        case message.command
          when 'ERROR' 
            ActiveMessaging.logger.error('Error from messaging infrastructure: ' + message.headers['message'])
          when 'MESSAGE'
            sent = false
            subscriptions.each do |subscription| 
              if subscription.matches?(message) then
                routing = {
                  :receiver=>subscription.processor_class, 
                  :queue=>subscription.destination,
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
        yield self
      end
      
      def queue queue_name, queue
        named_queues[queue_name] = queue
      end
      
      def find_queue queue_name
        real_queue = named_queues[queue_name]
        raise "You have not yet defined a queue named #{queue_name}. Queues currently defined are [#{named_queues.keys.join(',')}]" if real_queue.nil?
        real_queue
      end

      def trace_on queue
        @@trace_on = queue
      end

      def subscribe_to queue_name, processor
        proc_sym = processor.name.underscore.to_sym
        if (!current_processor_group || processor_groups[current_processor_group].include?(proc_sym))
          subscriptions << Subscription.new(find_queue(queue_name), processor)
        end
      end

      def publish queue_name, body, publisher=nil, headers = {}
        real_queue = find_queue(queue_name)
        details = {
          :publisher => publisher, 
          :queue => real_queue,
          :direction => :outgoing
        }
        message = OpenStruct.new(:body => body, :headers => headers)
        execute_filter_chain(:out, message, details) do |message|
          ActiveMessaging.connection(connection_configuration).send real_queue, message.body, message.headers
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
        if ARGV[0] && !@@current_processor_group
          first_pair = ARGV[0].split('=')
          if first_pair[0] == 'process-group'
            group_sym = first_pair[1].to_sym
            if processor_groups.has_key? group_sym
              @@current_processor_group = group_sym
            else
              puts "Unrecognized process-group."
              puts "You specified process-group #{first_pair[1]}, make sure this is specified in config/messaging.rb"
              puts "  ActiveMessaging::Gateway.define do |s|"
              puts "  s.processor_groups = { :group1 => [:foo_bar1_processor], :group2 => [:foo_bar2_processor] }"
              puts "  end"
              exit
            end
          else
            puts "Unrecognized option."
            puts "  Only process-group=foo is acceptable as a command line option."
            exit
          end
        end
        @@current_processor_group
      end
      
    end

  end
  
  class Subscription
    attr_reader :destination
    attr_reader :processor_class
    
    def initialize(destination, processor_class, options = {})
      @destination, @processor_class, @options = destination, processor_class, options
    end
    
    def matches?(message)
      message.headers['destination'].to_s == destination.to_s
    end
    
    def subscribe(connection)
      puts "=> Subscribing to #{destination} (processed by #{processor_class})"
      connection.subscribe(destination)
    end

    def unsubscribe(connection)
      puts "=> Unsubscribing from #{destination} (processed by #{processor_class})"
      connection.unsubscribe(destination)
    end
  end
  
end
