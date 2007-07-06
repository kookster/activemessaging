require 'logger'

module ActiveMessaging

  # This is a module so that we can send messages from (for example) web page controllers
  module MessageSender

    def self.included(included_by)
      class << included_by
        def publishes_to destination_name
          Gateway.find_destination destination_name
        end

        def receives_from destination_name
          Gateway.find_destination destination_name
        end
      end
    end

    def publish destination_name, message, headers={}, timeout=10
      Gateway.publish(destination_name, message, self.class, headers, timeout)
    end

    def receive destination_name, headers={}, timeout=10
      Gateway.receive(destination_name, self.class, headers, timeout)
    end

  end

  class Processor
    include MessageSender
    # include Reloadable
    
    attr_reader :message
  
    def logger()
      @@logger = ActiveMessaging.logger unless defined?(@@logger)
      @@logger
    end
    
    class<<self
      def subscribes_to destination_name, headers={}
        ActiveMessaging::Gateway.subscribe_to destination_name, self, headers
      end
    end
    
    # Bind the processor to the current message so that the processor could
    # potentially access headers and other attributes of the message
    def process!(message)
      @message = message
      on_message(message.body)
    rescue
      begin
        on_error($!)
      rescue
        logger.error "Processor:process! - error in on_error, will propagate no further: #{$!.message}"
      end
    end

  end
end