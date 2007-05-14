require 'yaml'

module ActiveMessaging

  class StopProcessingException < Interrupt #:nodoc:
  end

  def ActiveMessaging.logger
    @@logger = ActiveRecord::Base.logger unless defined?(@@logger)
    @@logger = Logger.new(STDOUT) unless defined?(@logger)
    @@logger
  end

  def ActiveMessaging.start
    if ActiveMessaging::Gateway.subscriptions.empty?
      puts "No subscriptions."
      puts "If you have no processor classes in app/processors, add them using the command:"
      puts "  script/generate processor DoSomething"
      puts "If you have processor classes, make sure they include in the class a call to 'subscribes_to':"
      puts "  class DoSomethingProcessor < ActiveMessaging::Processor"
      puts "    subscribes_to :do_something"
      exit
    end

    Gateway.start
  end

  class Gateway
    cattr_accessor :adapters, :subscriptions, :named_queues, :filters, :processor_groups
    @@adapters = {}
    @@subscriptions = {}
    @@named_queues = {}
    @@filters = []
    @@processor_groups = {}

    @@trace_on = nil
    @@current_processor_group = nil
    @@connections = {}
    @@running = true
    @@connection_threads = {}
    @@guard = Mutex.new
 
    class <<self

      def start
        #subscribe - creating connections along the way
        subscribe

        #for each conection, start a thread
        @@connections.each do |name, conn|
          @@connection_threads[name] = Thread.start do
            while @@running
              begin
                Thread.current[:message] = nil
                Thread.current[:message] = conn.receive
              rescue StopProcessingException
                puts "Processing Stopped - receive interrupted, will process last message if already received"
              ensure
                dispatch Thread.current[:message] if Thread.current[:message]
                Thread.current[:message] = nil
              end
              Thread.pass
            end
          end
        end
        
        while @@running
          trap("TERM", "EXIT")
          living = false
          @@connection_threads.each { |name, thread| living ||=  thread.alive? }
          @@running = living
          sleep 1
        end
        puts "All connection threads have died..."
      rescue Interrupt
        puts "\n<<Interrupt received>>\n"  
      rescue
        st = $!.backtrace.join("\n\t")
        puts "#{$!.class.name}: #{$!.message}\n\t#{st}"
        raise $!
      ensure
        puts "Cleaning up..."
        stop
        puts "=> END"
      end
      
      def stop
        # first tell the threads to stop their looping, so they'll stop when next complete a receive/dispatch cycle
        @@running = false
        
        # if they are dispatching (i.e. !thread[:message].nil?), wait for them to finish
        # if they are receiving (i.e. thread[:message].nil?), stop them by raising exception
        dispatching = true
        while dispatching
          dispatching = false
          @@connection_threads.each do |name, thread|
            if thread[:message]
              dispatching = true
              # if thread got killed, but dispatch not done, try it again
              if thread.alive?
                puts "Waiting on thread #{name} to finish processing last message..."
              else
                puts "Starting thread #{name} to finish processing last message..."
                msg = thread[:message]
                thread.exit
                thread = Thread.start do
                  begin 
                    Thread.current[:message] = msg
                    dispatch Thread.current[:message]
                  ensure
                    Thread.current[:message] = nil
                  end
                end
              end
            else
              thread.raise StopProcessingException, "Time to stop." if thread.alive?
            end
          end
          sleep(1)
        end
        unsubscribe
        disconnect
      end
      
      def connection broker_name='default'
        return @@connections[broker_name] if @@connections.has_key?(broker_name)
        config = load_connection_configuration(broker_name)
        @@connections[broker_name] = Gateway.adapters[config[:adapter]].new(config)
      end

      def register_adapter adapter_name, adapter_class
        adapters[adapter_name] = adapter_class
      end
      
      def filter filter, options = {}
        options[:direction] = :bidirectional if options[:direction].nil?
        filters << [filter, options]
      end
      
      def subscribe
        subscriptions.each { |key, subscription| subscription.subscribe }
      end

      def unsubscribe
        subscriptions.each { |key, subscription| subscription.unsubscribe }
      end

      def disconnect
        @@connections.each { |key,connection| connection.disconnect }
      end

      def dispatched subscription, message
        connection(subscription.queue.broker_name).received message
      end
      
      def execute_filter_chain(direction, message, details={})
        filters.each do |filter, options|
            if direction.to_sym == options[:direction] || options[:direction] == :bidirectional
              exit_flag = true
              filter.process(message, details) do 
                exit_flag = false
              end
              return if exit_flag
            end
        end
        yield(message)
      end

      def prepare_application
        # puts "Calling prepare_application!"
        Dispatcher.prepare_application_for_dispatch
        # puts "Called prepare_application"
      end

      def reset_application
        # puts "Calling reset_application!"
        Dispatcher.reset_application_after_dispatch
      end
      
      def dispatch(message)
        @@guard.synchronize {
          begin
            prepare_application
            _dispatch(message)
          rescue Object => exc
            STDERR.puts "Dispatch exception: #{exc}"
            STDERR.puts $!.backtrace.join("\n\t")
            raise $!
          ensure
            reset_application
          end
        }
      end

      def _dispatch(message)
        case message.command
        when 'ERROR'
          ActiveMessaging.logger.error('Error from messaging infrastructure: ' + message.headers['message'])
        when 'MESSAGE'
          ack = true
          subscriptions.each do |key, subscription| 
            if subscription.matches?(message) then
              routing = {
                :receiver=>subscription.processor_class, 
                :queue=>subscription.queue,
                :direction => :incoming
              }
              execute_filter_chain(:in, message, routing) do |m| 
                subscription.processor_class.new.process!(m)
              end
            
              dispatched subscription, message if ack
              ack = false
            end
          end
          ActiveMessaging.logger.error("No-one responded to #{message}") if ack
        else 
          ActiveMessaging.logger.error('Unknown message command: ' + message.inspect)
        end
      end

      def define
        #run the rest of messaging.rb
        yield self
      end
      
      def queue queue_name, queue, publish_headers={}, broker='default'
        named_queues[queue_name] = Queue.new queue_name, queue, publish_headers, broker
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
        proc_name = processor.name.underscore
        proc_sym = processor.name.underscore.to_sym
        if (!current_processor_group || processor_groups[current_processor_group].include?(proc_sym))
          @@subscriptions["#{proc_name}:#{queue_name}"]= Subscription.new(find_queue(queue_name), processor, headers)
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
          connection(real_queue.broker_name).send real_queue.destination, message.body, message.headers
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
                puts "    s.processor_groups = { :group1 => [:foo_bar1_processor], :group2 => [:foo_bar2_processor] }"
                puts "  end"
                exit
              end
            end
          }
        end
        @@current_processor_group
      end
      
      def load_connection_configuration(label='default')
        broker_config = YAML.load_file(File.join(RAILS_ROOT, 'config', 'broker.yml'))
        if label == 'default'
          config = broker_config[RAILS_ENV].symbolize_keys
        else
          config = broker_config[RAILS_ENV][label].symbolize_keys
        end
        config[:adapter] = config[:adapter].to_sym if config[:adapter]
        config[:adapter] ||= :stomp
        return config
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
      message.headers['destination'].to_s == @queue.destination.to_s
    end
    
    def subscribe
      puts "=> Subscribing to #{queue.destination} (processed by #{processor_class})"
      Gateway.connection(queue.broker_name).subscribe(queue.destination, subscribe_headers) 
    end

    def unsubscribe
      puts "=> Unsubscribing from #{queue.destination} (processed by #{processor_class})"
      Gateway.connection(queue.broker_name).unsubscribe(queue.destination, subscribe_headers)
    end
  end

  class Queue
    DEFAULT_PUBLISH_HEADERS = { :persistent=>true }

    attr_accessor :name, :destination, :publish_headers, :broker_name

    def initialize(name, destination, publish_headers, broker_name)
      @name, @destination, @publish_headers, @broker_name = name, destination, publish_headers, broker_name
      @publish_headers.reverse_merge! DEFAULT_PUBLISH_HEADERS
    end
  end

end #module
