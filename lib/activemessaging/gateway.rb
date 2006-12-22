module ActiveMessaging
  
  def ActiveMessaging.logger
    @@logger = ActiveRecord::Base.logger unless defined?(@@logger)
    @@logger
  end

  def ActiveMessaging.connection  
    @@connection = ActiveMessaging::Adapters::Stomp::Connection.new({}) unless defined?(@@connection)
    @@connection
  end
  
  class Gateway
    cattr_accessor :subscriptions, :named_queues, :filters
    @@filters = []
    @@subscriptions = []
    @@named_queues = {}
    @@trace_on = nil
 
    class <<self
      
      def filter filter, options = {}
        filters << filter
      end

      def subscribe
        subscriptions.each do |subscription|
          subscription.subscribe(ActiveMessaging.connection)
        end
      end

      def dispatch_next
        dispatch(ActiveMessaging.connection.receive)
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
              subscriptions.find do |subscription| 
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
        subscriptions << Subscription.new(find_queue(queue_name), processor)
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
          ActiveMessaging.connection.send real_queue, message.body, message.headers
        end
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
  end
  
end
