class <%= class_name %>Processor < ActiveMessaging::Processor
  def on_message(message)
    puts "received: " + message
  end
end