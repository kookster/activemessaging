# # experimenting with adding processors to the load paths, doesn't seem to work
# Dependencies.load_paths += ["#{RAILS_ROOT}/app/processors"]

require 'dispatcher' unless defined?(::Dispatcher)
::Dispatcher.class_eval do

  def self.prepare_application_for_dispatch
    if (self.private_methods.include? "prepare_application")
      prepare_application
    else
      disp = new(STDOUT)
      if disp.respond_to?(:prepare_application)
        disp.prepare_application 
      elsif disp.respond_to?(:reload_application)
        disp.reload_application
      end
    end
  end  

  def self.reset_application_after_dispatch
    if (self.private_methods.include? "reset_after_dispatch")
      reset_after_dispatch
    else
      disp = new(STDOUT)
      if disp.respond_to?(:cleanup_application)
        disp.cleanup_application 
      end
    end
  end
  
end
