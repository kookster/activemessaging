# 'abstract' base class for ActiveMessaging processor classes
module ActiveMessaging

  class Processor
    include MessageSender
    
    attr_reader :message
  
    class<<self
      def subscribes_to destination_name, headers={}
        ActiveMessaging::Gateway.subscribe_to destination_name, self, headers
      end
    end

    def logger()
      @@logger = ActiveMessaging.logger unless defined?(@@logger)
      @@logger
    end
    
    def on_message(message)
      raise NotImplementedError.new("Implement the on_message method in your own processor class that extends ActiveMessaging::Processor")
    end

    def on_error(exception)
      raise exception
    end
    
    # Bind the processor to the current message so that the processor could
    # potentially access headers and other attributes of the message
    def process!(message)
      @message = message
      return on_message(message.body)
    rescue Object=>err
      begin
        on_error(err)
      rescue ActiveMessaging::AbortMessageException => rpe
        logger.error "Processor:process! - AbortMessageException caught."
        raise rpe
      rescue Object=>ex
        logger.error "Processor:process! - error in on_error, will propagate no further: #{ex.message}"
      end
    end

  end
end