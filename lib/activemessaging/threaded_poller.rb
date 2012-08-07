# still working on prioritized worker requests


# This owes no small debt to sidekiq for showing how to use celluloid for polling for messages.
# https://github.com/mperham/sidekiq/blob/poller/lib/sidekiq/manager.rb
if RUBY_VERSION.to_f >= 1.9 # Celluloid requires fibers support, which is not available on 1.8
require 'celluloid'

module ActiveMessaging

  class ThreadedPoller

    include Celluloid

    # traps when any worker dies
    trap_exit :died

    attr_accessor :configuration, :receiver, :connection, :workers, :busy, :running

    # 
    # connection is a string, name of the connection from broker.yml to use for this threaded poller instance
    # 
    # configuration is a list of hashes
    # each has describes a group of worker threads
    # for each group, define what priorities those workers will process
    #   [
    #     {
    #       :pool_size  => 1       # number of workers of this type
    #       :priorities => [1,2,3] # what message priorities this thread will process
    #     }
    #   ]
    # 
    def initialize(connection='default', configuration={})
      # default config is a pool size of 3 worker threads
      self.configuration = configuration || [{:pool_size => 3}]
      self.connection = connection
    end

    def start
      logger.info "ActiveMessaging::ThreadedPoller start"

      # these are workers ready to use
      self.workers = []
      
      # these are workers already working
      self.busy = []
      
      # this indicates if we are running or not, helps threads to stop gracefully
      self.running = true
      
      # subscribe will create the connections based on subscriptions in processsors
      # (you can't find or use the connection until it is created by calling this)
      ActiveMessaging::Gateway.subscribe
      
      # create a message receiver actor, ony need one, using connection
      receiver_connection = ActiveMessaging::Gateway.connection(connection)
      self.receiver = MessageReceiver.new(current_actor, receiver_connection)
      
      # start the workers based on the config
      configuration.each do |c|
        (c[:pool_size] || 1).times{ self.workers << Worker.new_link(current_actor, c) }
      end

      # once all workers are created, start them up
      self.workers.each{|worker| receive(worker)}

      # in debug level, log info about workers every 10 seconds
      log_status
    end

    def stop
      logger.info "ActiveMessaging::ThreadedPoller stop"
      # indicates to all busy workers not to pick up another messages, but does not interrupt
      # also indicates to the message receiver to stop getting more messages 
      self.running = false

      # tell each waiting worker to shut down.  Running ones will be allowed to finish
      receiver.terminate! if receiver.alive?
      logger.info "ActiveMessaging::ThreadedPoller receiver terminated"

      workers.each { |w| w.terminate! if w.alive? }
      logger.info "ActiveMessaging::ThreadedPoller workers terminated"


      after(0) { signal(:shutdown) } if stopped?
    end

    # recursive method, uses celluloid 'after' to keep calling 
    def log_status
      return unless logger.debug?
      logger.debug("ActiveMessaging::ThreadedPoller: conn:#{connection}, #{workers.count}, #{busy.count}, #{running}")
      after(10){ log_status }
    end

    def receive(worker)
      receiver.receive!(worker) if (receiver && running && worker)
    end

    def dispatch(message, worker)
      workers.delete(worker)
      busy << worker
      worker.execute!(message)
    end
    
    def executed(worker)
      busy.delete(worker)

      if running
        workers << worker
        receive(worker)
      else
        worker.terminate if worker.alive?
        if busy.empty?
          logger.info "all executed: signal stopped"
          after(0) { signal(:shutdown) }
        end
      end
    end

    def died(worker, reason)
      busy.delete(worker)

      if running
        logger.info "uh oh, #{worker.inspect} died because of #{reason.class}"
        worker = Worker.new_link(current_actor)
        workers << worker
        receive(worker)
      else
        logger.info "check to see if busy is empty: #{busy.inspect}"
        if busy.empty?
          logger.info "all died: signal stopped"
          after(0){ signal(:shutdown) }
        end
      end
    end
    
    def stopped?
      (!running && busy.empty?)
    end

    def logger; ActiveMessaging.logger; end

  end

  class MessageReceiver
    include Celluloid

    attr_accessor :poller, :connection, :pause

    def initialize(poller, connection, pause=1)
      logger.debug("MessageReceiver initialize: poller:#{poller}, connection:#{connection}, pause:#{pause}")
      
      raise "No connection found for '#{poller.connection}'" unless connection
      
      self.poller     = poller
      self.connection = connection
      self.pause      = pause
    end

    def receive(worker)
      return unless poller.running

      # logger.debug("***** MessageReceiver calling receive")
      message = self.connection.receive(worker.options)
      # logger.debug("***** MessageReceiver receive returned")

      if message
        logger.debug("ActiveMessaging::MessageReceiver.receive: message:'#{message.inspect}'")
        poller.dispatch!(message, worker)
      else
        if (!poller || !poller.alive? || !poller.running)
          logger.debug("ActiveMessaging::MessageReceiver.receive: terminate")
          self.terminate
        end
        logger.debug("ActiveMessaging::MessageReceiver.receive: no message, retry in #{pause} sec")
        after(pause) { receive(worker) }
      end
      
    end

    def logger; ::ActiveMessaging.logger; end
  end

  class Worker
    include Celluloid

    attr_accessor :poller, :options

    def initialize(poller, options)
      self.poller = poller
      self.options = options
    end

    def execute(message)
      begin
        ::ActiveMessaging::Gateway.dispatch(message)
      ensure
        ::ActiveRecord::Base.clear_active_connections! if defined?(::ActiveRecord)
      end

      poller.executed!(current_actor)
    end

    def logger; ::ActiveMessaging.logger; end
    
  end

end
end # if RUBY_VERSION
