require 'dispatcher' unless defined?(::Dispatcher)
::Dispatcher.class_eval do

  def self.prepare_application_for_dispatch
    prepare_application
  end  

  def self.reset_application_after_dispatch
    reset_after_dispatch
  end

end
