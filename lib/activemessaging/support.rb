require 'dispatcher' unless defined?(::Dispatcher)
::Dispatcher.class_eval do

  def self.prepare_application_for_dispatch
    if (self.private_methods.include? "prepare_application")
      prepare_application
    else
      new(STDOUT).prepare_application
    end
  end  

  def self.reset_application_after_dispatch
    if (self.private_methods.include? "reset_after_dispatch")
      reset_after_dispatch
    else
      new(STDOUT).cleanup_application
    end
  end
  
end
