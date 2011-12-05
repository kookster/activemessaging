class <%= class_name %>Processor < ApplicationProcessor

  subscribes_to :<%= singular_name %>

  def on_message(message)
    logger.debug "<%= class_name %>Processor received: " + message
  end
end