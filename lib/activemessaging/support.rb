require 'dispatcher' unless defined?(::Dispatcher)
::Dispatcher.class_eval do

  def self.prepare_application_for_dispatch
    prepare_application
  end  

  def self.reset_application_after_dispatch
    reset_after_dispatch
  end
  
  # unless ::Dispatcher.respond_to?(:to_prepare)
  #   
  #   def prepare_application
  #     ActiveMessaging.reload_activemessaging
  #     ActionController::Routing::Routes.reload if Dependencies.load?
  #     prepare_breakpoint
  #     require_dependency('application.rb') unless Object.const_defined?(:ApplicationController)
  #     ActiveRecord::Base.verify_active_connections!
  #   end
  # 
  # end
  

end
