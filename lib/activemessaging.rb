module ActiveMessaging

  VERSION = "0.5" #maybe this should be higher, but I'll let others judge :)

  class StopProcessingException < Interrupt #:nodoc:
  end

  def ActiveMessaging.logger
    @@logger = ActiveRecord::Base.logger unless defined?(@@logger)
    @@logger = Logger.new(STDOUT) unless defined?(@@logger)
    @@logger
  end

  # DEPRECATED, so I understand, but I'm using it nicely below.
  def self.load_extensions
    require 'activemessaging/gateway'
    require 'activemessaging/processor'
    require 'activemessaging/trace_filter'
    require 'activemessaging/adapter'
    require 'activemessaging/support'
    require 'logger'

    # load all under the adapters dir 
    Dir[RAILS_ROOT + '/vendor/plugins/activemessaging/lib/activemessaging/adapters/*.rb'].each{|a| 
      begin
        adapter_name = File.basename(a, ".rb")
        require 'activemessaging/adapters/' + adapter_name
      rescue RuntimeError, LoadError => e
        logger.debug "ActiveMessaging: adapter #{adapter_name} not loaded: #{ e.message }"
      end
    }
  end

  def self.load_config
    path = File.expand_path("#{RAILS_ROOT}/config/messaging.rb")
    begin
      load path
    rescue MissingSourceFile
      logger.debug "ActiveMessaging: no '#{path}' file to load"
    rescue
      raise $!, " ActiveMessaging: problems trying to load '#{path}'"
    end
  end

  def self.load_processors(first=true)
    #Load the parent processor.rb, then all child processor classes
    load RAILS_ROOT + '/vendor/plugins/activemessaging/lib/activemessaging/processor.rb' unless defined?(ActiveMessaging::Processor)
    logger.debug "ActiveMessaging: Loading #{RAILS_ROOT + '/app/processors/application.rb'}" if first
    load RAILS_ROOT + '/app/processors/application.rb'
    Dir[RAILS_ROOT + '/app/processors/*.rb'].each do |f|
      unless f.match(/\/application.rb/)
        logger.debug "ActiveMessaging: Loading #{f}" if first
        load f
      end
    end
  end

  def self.reload_activemessaging
    # puts "Called: reload_activemessaging"    
    load_config
    load_processors(false)
  end

  def self.load_activemessaging
    load_extensions
    load_config
    load_processors
  end

  def self.start
    if ActiveMessaging::Gateway.subscriptions.empty?
      err_msg = <<EOM   

ActiveMessaging Error: No subscriptions.
If you have no processor classes in app/processors, add them using the command:
  script/generate processor DoSomething"

If you have processor classes, make sure they include in the class a call to 'subscribes_to':
  class DoSomethingProcessor < ActiveMessaging::Processor
    subscribes_to :do_something

EOM
      puts err_msg
      logger.error err_msg
      exit
    end

    Gateway.start
  end

end

#load these once to start with
ActiveMessaging.load_extensions
ActiveMessaging.load_config

#load these on each request - leveraging Dispatcher semantics for consistency
require 'dispatcher' unless defined?(::Dispatcher)

# add processors and config to on_prepare if supported (rails 1.2+)
if ::Dispatcher.respond_to? :to_prepare
  ::Dispatcher.to_prepare :activemessaging do
    ActiveMessaging.reload_activemessaging
  end
end
