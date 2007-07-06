require 'yaml'

module ActiveMessaging

  class Gateway
    cattr_accessor :adapters, :subscriptions, :named_destinations, :filters, :processor_groups, :connections
    @@adapters = {}
    @@subscriptions = {}
    @@named_destinations = {}
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
                puts "ActiveMessaging: thread[#{name}]: Processing Stopped - receive interrupted, will process last message if already received"
              rescue Object=>exception
                puts "ActiveMessaging: thread[#{name}]: Exception from connection.receive: #{exception.message}\n" + exception.backtrace.join("\n\t")
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
      rescue Object=>exception
        st = exception.backtrace.join("\n\t")
        puts "#{exception.class.name}: #{exception.message}\n\t#{st}"
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
        @@connections = {}
      end

      def dispatched subscription, message
        connection(subscription.destination.broker_name).received message, subscription.subscribe_headers
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
                :destination=>subscription.destination,
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

      def destination destination_name, destination, publish_headers={}, broker='default'
        # raise "You already defined #{destination_name} to #{named_destinations[destination_name].value}" if named_destinations.has_key?(destination_name)
        named_destinations[destination_name] = Destination.new destination_name, destination, publish_headers, broker
      end
      
      alias queue destination
      
      def find_destination destination_name
        real_destination = named_destinations[destination_name]
        raise "You have not yet defined a destination named #{destination_name}. Destinations currently defined are [#{named_destinations.keys.join(',')}]" if real_destination.nil?
        real_destination
      end

      alias find_queue find_destination

      def trace_on destination
        @@trace_on = destination
      end

      def subscribe_to destination_name, processor, headers={}
        proc_name = processor.name.underscore
        proc_sym = processor.name.underscore.to_sym
        if (!current_processor_group || processor_groups[current_processor_group].include?(proc_sym))
          @@subscriptions["#{proc_name}:#{destination_name}"]= Subscription.new(find_destination(destination_name), processor, headers)
        end
      end

      def publish destination_name, body, publisher=nil, headers={}, timeout=10
        raise "You cannot have a nil or empty destination name." if destination_name.nil?
        raise "You cannot have a nil or empty message body." if (body.nil? || body.empty?)
        
        real_destination = find_destination(destination_name)
        details = {
          :publisher => publisher, 
          :destination => real_destination,
          :direction => :outgoing
        }
        message = OpenStruct.new(:body => body, :headers => headers.reverse_merge(real_destination.publish_headers))
        begin
          Timeout.timeout timeout do
            execute_filter_chain(:out, message, details) do |message|
              connection(real_destination.broker_name).send real_destination.value, message.body, message.headers
            end
          end
        rescue Timeout::Error=>toe
          ActiveMessaging.logger.error("Timed out trying to send the message #{message} to destination #{destination_name} via broker #{real_destination.broker_name}")
          raise toe
        end
      end
      
      def receive destination_name, receiver=nil, subscribe_headers={}, timeout=10
        raise "You cannot have a nil or empty destination name." if destination_name.nil?
        conn = nil
        dest = find_destination destination_name
        config = load_connection_configuration(dest.broker_name)
        subscribe_headers['id'] = receiver.name.underscore unless (receiver.nil? or subscribe_headers.key? 'id') 
        Timeout.timeout timeout do
          conn = Gateway.adapters[config[:adapter]].new(config)
          conn.subscribe(dest.value, subscribe_headers)
          message = conn.receive
          conn.received message, subscribe_headers
          return message
        end
      rescue Timeout::Error=>toe
        ActiveMessaging.logger.error("Timed out trying to receive a message on destination #{destination_name}")
        raise toe
      ensure
        conn.disconnect unless conn.nil?
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
        @broker_yml = YAML.load_file(File.join(RAILS_ROOT, 'config', 'broker.yml')) if @broker_yml.nil?
        if label == 'default'
          config = @broker_yml[RAILS_ENV].symbolize_keys
        else
          config = @broker_yml[RAILS_ENV][label].symbolize_keys
        end
        config[:adapter] = config[:adapter].to_sym if config[:adapter]
        config[:adapter] ||= :stomp
        return config
      end
      
    end

  end

  class Subscription
    attr_accessor :destination, :processor_class, :subscribe_headers
        
    def initialize(destination, processor_class, subscribe_headers = {})
      @destination, @processor_class, @subscribe_headers = destination, processor_class, subscribe_headers
      subscribe_headers['id'] = processor_class.name.underscore unless subscribe_headers.key? 'id'
    end
    
    def matches?(message)
      message.headers['destination'].to_s == @destination.value.to_s
    end
    
    def subscribe
      puts "=> Subscribing to #{destination.value} (processed by #{processor_class})"
      Gateway.connection(@destination.broker_name).subscribe(@destination.value, subscribe_headers) 
    end

    def unsubscribe
      puts "=> Unsubscribing from #{destination.value} (processed by #{processor_class})"
      Gateway.connection(destination.broker_name).unsubscribe(destination.value, subscribe_headers)
    end
  end

  class Destination
    DEFAULT_PUBLISH_HEADERS = { :persistent=>true }

    attr_accessor :name, :value, :publish_headers, :broker_name

    def initialize(name, value, publish_headers, broker_name)
      @name, @value, @publish_headers, @broker_name = name, value, publish_headers, broker_name
      @publish_headers.reverse_merge! DEFAULT_PUBLISH_HEADERS
    end
    
    def to_s
      "#{broker_name}: #{name} => '#{value}'"
    end

  end

end #module
