require 'yaml'

module ActiveMessaging

  class Gateway
    cattr_accessor :adapters, :subscriptions, :named_destinations, :filters, :processor_groups, :connections
    @@adapters = {}
    @@subscriptions = {}
    @@named_destinations = {}
    @@filters = []
    @@connections = {}
    @@processor_groups = {}
    @@current_processor_group = nil

    # these are used to manage the running connection threads
    @@running = true
    @@connection_threads = {}
    @@guard = Mutex.new
 
    class <<self

      # Starts up an message listener to start polling for messages on each configured connection, and dispatching processing
      def start

        # subscribe - creating connections along the way
        subscribe

        # for each connection, start a thread
        @@connections.each do |name, conn|
          @@connection_threads[name] = Thread.start do
            while @@running
              begin
                Thread.current[:message] = nil
                Thread.current[:message] = conn.receive
              #catch these but then stop looping
              rescue StopProcessingException=>spe
                ActiveMessaging.logger.error "ActiveMessaging: thread[#{name}]: Processing Stopped - receive interrupted, will process last message if already received"
                # break
              #catch all others, but go back and try and recieve again
              rescue Object=>exception
                ActiveMessaging.logger.error "ActiveMessaging: thread[#{name}]: Exception from connection.receive: #{exception.message}\n" + exception.backtrace.join("\n\t")
              ensure
                dispatch Thread.current[:message] if Thread.current[:message]
                Thread.current[:message] = nil
              end
              Thread.pass
            end
            ActiveMessaging.logger.error "ActiveMessaging: thread[#{name}]: receive loop terminated"
          end
        end
        
        while @@running
          trap("TERM", "EXIT")
          living = false
          @@connection_threads.each { |name, thread| living ||=  thread.alive? }
          @@running = living
          sleep 1
        end
        ActiveMessaging.logger.error "All connection threads have died..."
      rescue Interrupt
        ActiveMessaging.logger.error "\n<<Interrupt received>>\n"  
      rescue Object=>exception
        ActiveMessaging.logger.error "#{exception.class.name}: #{exception.message}\n\t#{exception.backtrace.join("\n\t")}"
        raise exception
      ensure
        ActiveMessaging.logger.error "Cleaning up..."
        stop
        ActiveMessaging.logger.error "=> END"
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
                ActiveMessaging.logger.error "Waiting on thread #{name} to finish processing last message..."
              else
                ActiveMessaging.logger.error "Starting thread #{name} to finish processing last message..."
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

      def execute_filter_chain(direction, message, details={})
        filters.each do |filter, options|
          if apply_filter?(direction, details, options)
            begin
              filter_obj = create_filter(filter, options)
              filter_obj.process(message, details)
            rescue ActiveMessaging::StopFilterException => sfe
              ActiveMessaging.logger.error "Filter: #{filter_obj.inspect} threw StopFilterException: #{sfe.message}"
              return
            end
          end
        end
        yield(message)
      end
      
      def apply_filter?(direction, details, options)
        # check that it is the correct direction
        result = if direction.to_sym == options[:direction] || options[:direction] == :bidirectional
          if options.has_key?(:only) && [options[:only]].flatten.include?(details[:destination].name)
            true
          elsif options.has_key?(:except) && ![options[:except]].flatten.include?(details[:destination].name)
            true
          elsif !options.has_key?(:only) && !options.has_key?(:except)
            true
          end
        end
        result
      end

      def create_filter(filter, options)
        filter_class = if filter.is_a?(String) or filter.is_a?(Symbol)
          filter.to_s.camelize.constantize
        elsif filter.is_a?(Class)
          filter
        end

        if filter_class
          if filter_class.respond_to?(:process) && (filter_class.method(:process).arity.abs > 0)
            filter_class
          elsif filter_class.instance_method(:initialize).arity.abs == 1
            filter_class.new(options)
          elsif filter_class.instance_method(:initialize).arity == 0
            filter_class.new
          else
            raise "Filter #{filter} could not be created, no 'initialize' matched."
          end
        else
          raise "Filter #{filter} could not be loaded, created, or used!"
        end
      end

      def prepare_application
        Dispatcher.prepare_application_for_dispatch
      end

      def reset_application
        Dispatcher.reset_application_after_dispatch
      end
      
      def dispatch(message)
        @@guard.synchronize {
          begin
            prepare_application
            _dispatch(message)
          rescue Object => exc
            ActiveMessaging.logger.error "Dispatch exception: #{exc}"
            ActiveMessaging.logger.error exc.backtrace.join("\n\t")
            raise exc
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
          abort = false
          processed = false

          subscriptions.each do |key, subscription| 
            if subscription.matches?(message) then
              processed = true
              routing = {
                :receiver=>subscription.processor_class, 
                :destination=>subscription.destination,
                :direction => :incoming
              }
              begin
                execute_filter_chain(:incoming, message, routing) do |m|
                  result = subscription.processor_class.new.process!(m)
                end
              rescue ActiveMessaging::AbortMessageException
                abort_message subscription, message
                abort = true
                return
              ensure
                acknowledge_message subscription, message unless abort
              end
            end
          end

          ActiveMessaging.logger.error("No-one responded to #{message}") unless processed
        else 
          ActiveMessaging.logger.error('Unknown message command: ' + message.inspect)
        end
      end

      # acknowledge_message is called when the message has been processed w/o error by at least one processor
      def acknowledge_message subscription, message
        connection(subscription.destination.broker_name).received message, subscription.subscribe_headers
      end

      # abort_message is called when procesing the message raises a ActiveMessaging::AbortMessageException
      # indicating the message should be returned to the destination so it can be tried again, later
      def abort_message subscription, message
        connection(subscription.destination.broker_name).unreceive message, subscription.subscribe_headers
      end

      def define
        #run the rest of messaging.rb
        yield self
      end

      def destination destination_name, destination, publish_headers={}, broker='default'
        raise "You already defined #{destination_name} to #{named_destinations[destination_name].value}" if named_destinations.has_key?(destination_name)
        named_destinations[destination_name] = Destination.new destination_name, destination, publish_headers, broker
      end
      
      alias queue destination
      
      def find_destination destination_name
        real_destination = named_destinations[destination_name]
        raise "You have not yet defined a destination named #{destination_name}. Destinations currently defined are [#{named_destinations.keys.join(',')}]" if real_destination.nil?
        real_destination
      end

      alias find_queue find_destination

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
            execute_filter_chain(:outgoing, message, details) do |message|
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
                ActiveMessaging.logger.error "Unrecognized process-group."
                ActiveMessaging.logger.error "You specified process-group #{pair[1]}, make sure this is specified in config/messaging.rb"
                ActiveMessaging.logger.error "  ActiveMessaging::Gateway.define do |s|"
                ActiveMessaging.logger.error "    s.processor_groups = { :group1 => [:foo_bar1_processor], :group2 => [:foo_bar2_processor] }"
                ActiveMessaging.logger.error "  end"
                exit
              end
            end
          }
        end
        @@current_processor_group
      end
      
      def load_connection_configuration(label='default')
        @broker_yml = YAML::load(ERB.new(IO.read(File.join(RAILS_ROOT, 'config', 'broker.yml'))).result) if @broker_yml.nil?
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
      ActiveMessaging.logger.error "=> Subscribing to #{destination.value} (processed by #{processor_class})"
      Gateway.connection(@destination.broker_name).subscribe(@destination.value, subscribe_headers) 
    end

    def unsubscribe
      ActiveMessaging.logger.error "=> Unsubscribing from #{destination.value} (processed by #{processor_class})"
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
