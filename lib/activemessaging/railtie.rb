require 'logger'
require 'rails'
require 'activemessaging'

module ActiveMessaging
  class Railtie < Rails::Railtie
    initializer 'activemessaging.initialize' do
      
      ActiveMessaging.load_activemessaging

      # Add a to_prepare block which is executed once in production
      # and before each request in development
      if defined? Rails
        ActiveMessaging.logger.info "ActiveMessaging: Rails available: Adding dispatcher prepare callback."
        case
          when Gem::Version.new(Rails.version) < Gem::Version.new('3.0.0')
            ActionDispatch::Callbacks.to_prepare do
              ActiveMessaging.reload_activemessaging
            end
          else
            config.to_prepare do
              ActiveMessaging.reload_activemessaging
            end
        end
      end
    end

    rake_tasks do
      load "tasks/start_consumers.rake"
    end
  end
end
