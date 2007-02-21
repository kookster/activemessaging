require 'logger'

module ActiveMessaging

  # This is a module so that we can send messages from (for example) web page controllers
  module MessageSender

    def self.included(included_by)
      class << included_by
        def publishes_to queueName
          Gateway.find_queue queueName
        end
      end
    end

    def publish queue_name, message, headers={}
      Gateway.publish(queue_name, message, self.class, headers)
    end

  end

  class Processor
    include Reloadable::Subclasses
    include MessageSender
    
    attr_reader :message
  
    def logger()
      @@logger = ActiveMessaging.logger unless defined?(@@logger)
      @@logger
    end
    
    class<<self
      def subscribes_to queueName, headers={}
        Gateway.subscribe_to queueName, headers
      end
    end
    
    # Bind the processor to the current message so that the processor could
    # potentially access headers and other attributes of the message
    def process!(message)
      @message = message
      on_message(message.body)
    rescue
      on_error($!)
    end

  end
end