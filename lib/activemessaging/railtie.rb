require 'logger'
require 'rails'
require 'activemessaging'

module ActiveMessaging
  class Railtie < Rails::Railtie
    
    initializer 'activemessaging.initialize' do
      
      ActiveMessaging.load_activemessaging
      
      if defined? Rails
        ActiveMessaging.logger.info "ActiveMessaging: Rails available: Adding dispatcher prepare callback."
        ActionDispatch::Callbacks.to_prepare do
          ActiveMessaging.reload_activemessaging
        end
      end

    end
    
  end
end
