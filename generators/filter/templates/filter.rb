class <%= class_name %>Filter < ActiveMessaging::Filter

  attr_accessor :options
  
  def initialize(options={})
    @options = options
  end

  def process(message, routing)
    logger.debug "<%= class_name %>Filter filtering message: #{message.inspect} with routing: #{routing.inspect}"
  end
end