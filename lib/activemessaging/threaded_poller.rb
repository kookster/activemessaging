# This owes no small debt to sidekiq for showing how to use celluloid for polling for messages.
# https://github.com/mperham/sidekiq/blob/master/lib/sidekiq/manager.rb

require 'celluloid'

module ActiveMessaging

  class ThreadedPoller
    include Celluloid

    trap_exit :died

    attr_accessor :receiver, :connection, :pool_size, :workers, :busy, :running

    def initialize(connection='default', pool_size=3)
      self.pool_size = pool_size
      self.connection = connection
      puts "subscribe"
      ActiveMessaging::Gateway.subscribe
    end

    def start
      self.workers = []
      self.busy = []
      self.running = true
      # create a message receiver actor
      puts "ThreadedPoller start"
      self.receiver = MessageReceiver.new(current_actor, ActiveMessaging::Gateway.connection(connection))
      self.workers = pool_size.times.collect{|i| Worker.new_link(current_actor)}
      pool_size.times{ receive }
      log_status
    end

    def stop
      self.running = false
      workers.each { |w| w.terminate if w.alive? }
    end

    def log_status
      ActiveMessaging.logger.info("ActiveMessaging::ThreadedPoller: #{connection}, #{pool_size}, #{workers.count}, #{busy.count}, #{running}")
      after(5){ log_status }
    end

    def dispatch(message)
      worker = workers.pop
      busy << worker
      worker.execute!(message)
    end

    def receive
      receiver.receive! if (receiver && running)
    end

    def executed(worker)
      busy.delete(worker)
      workers << worker if worker.alive?

      if running
        receive
      else
        worker.terminate if worker.alive?
        if busy.empty?
          puts "all executed: signal stopped"
          signal(:shutdown)
        end
      end
    end

    def died(worker, reason)
      puts "uh oh, #{worker.inspect} died because of #{reason.class}"
      busy.delete(worker)

      if running
        workers << Processor.new_link(current_actor)
        receive
      else
        puts "check to see if busy is empty: #{busy.inspect}"
        if busy.empty?
          puts "all died: signal stopped"
          after(0){ signal(:shutdown) }
        end
      end
    end

  end

  class MessageReceiver
    include Celluloid

    attr_accessor :poller, :connection, :pause

    def initialize(poller, connection, pause=1)
      puts "MessageReceiver initialize"
      self.poller = poller
      self.connection = connection
      self.pause = pause
    end

    def receive
      return unless poller.running

      message = self.connection.receive

      if message
        puts "message: #{message.inspect}"
        poller.dispatch!(message)
      else
        if poller.running
          puts "no message, schedule recursive retry"
          after(pause) { receive }
        else
          terminate if alive?
        end
      end
    end

  end

  class Worker
    include Celluloid

    attr_accessor :master

    def initialize(master)
      self.master = master
    end

    def execute(message)
      ActiveMessaging::Gateway.dispatch(message)
      master.executed!(current_actor)
    end
  end

end