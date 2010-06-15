if defined? Rails
#  ActiveMessaging.logger.debug "Rails available: Adding reload hooks."
#  require 'dispatcher' unless defined?(::Dispatcher)
#  ::Dispatcher.class_eval do
#    
#    def self.prepare_application_for_dispatch
#      disp = new(STDOUT)
#      disp.run_callbacks :before_dispatch
#    end
#    
#    def self.reset_application_after_dispatch
#      disp = new(STDOUT)
#      disp.run_callbacks :after_dispatch, :enumerator => :reverse_each
#    end
#
#  end
end
