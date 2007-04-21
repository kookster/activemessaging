module ActiveMessaging

  VERSION = "0.5" #maybe this should be higher, but I'll let others judge :)

  # DEPRECATED, so I understand, but I'm using it nicely below.
  def self.load_extensions
    require 'activemessaging/gateway'
    require 'activemessaging/processor'
    require 'activemessaging/trace_filter'
    require 'activemessaging/adapter'
    require 'activemessaging/support'

    # load all under the adapters dir 
    Dir[RAILS_ROOT + '/vendor/plugins/activemessaging/lib/activemessaging/adapters/*.rb'].each{|a| 
      begin
        adapter_name = File.basename(a, ".rb")
        require 'activemessaging/adapters/' + adapter_name
      rescue RuntimeError, LoadError => e
        warn "Adapter #{adapter_name} not loaded: #{ e.message }"
      end
    }
  end

  def self.load_config
    begin
      load "#{RAILS_ROOT}/config/messaging.rb"
    rescue MissingSourceFile
    end
  end

  def self.load_processors(verbose=true)
    #Load the parent processor.rb, then all child processor classes
    puts "Loading #{RAILS_ROOT + '/app/processors/application.rb'}" if verbose
    load RAILS_ROOT + '/app/processors/application.rb'
    Dir[RAILS_ROOT + '/app/processors/*_processor.rb'].each{|f| puts "Loading #{f}" if verbose; load f}
  end

  def self.load_activemessaging
    load_extensions
    load_config
    load_processors
  end

end

#load these once to start with
ActiveMessaging.load_extensions

#load these on each request - leveraging Dispatcher semantics for consistency
require 'dispatcher' unless defined?(::Dispatcher)
::Dispatcher.to_prepare :activemessaging do
  base = File.dirname(__FILE__)
  ActiveMessaging.load_config
  ActiveMessaging.load_processors(false)
end
