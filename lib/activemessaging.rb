require 'active_support'
require 'ostruct'

if defined?(Rails::Railtie)
  require 'activemessaging/railtie.rb'
end

module ActiveMessaging

  ROOT = File.expand_path(File.join(File.dirname(__FILE__), '..'))

  # Used to indicate that the processing for a thread shoud complete
  class StopProcessingException < Interrupt #:nodoc:
  end

  # Used to indicate that the processing on a message should cease, 
  # and the message should be returned back to the broker as best it can be
  class AbortMessageException < Exception #:nodoc:
  end

  # Used to indicate that the processing on a message should cease, 
  # but no further action is required
  class StopFilterException < Exception #:nodoc:
  end

  def self.logger
    @@logger = nil unless defined? @@logger
    @@logger ||= Rails.logger if defined? Rails
    @@logger ||= Logger.new(STDOUT)
    @@logger
  end

  def self.logger=(logger)
    @@logger = logger
  end

  def self.app_root
    @@app_root ||= (ENV['APP_ROOT'] || (defined?(::Rails) && ::Rails.root) || ENV['RAILS_ROOT'] || File.dirname($0))
  end

  def self.app_env
    @@app_env  ||= (ENV['APP_ENV']  || (defined?(::Rails) && ::Rails.env)  || ENV['RAILS_ENV']  || 'development')
  end

  def self.load_extensions
    require 'logger'
    require 'activemessaging/gateway'
    require 'activemessaging/adapter'
    require 'activemessaging/message_sender'
    require 'activemessaging/processor'
    require 'activemessaging/filter'
    require 'activemessaging/trace_filter'

    # load all under the adapters dir 
    Dir[File.join(ROOT, 'lib', 'activemessaging', 'adapters', '*.rb')].each do |a| 
      begin
        adapter_name = File.basename(a, ".rb")
        require 'activemessaging/adapters/' + adapter_name
      rescue RuntimeError, LoadError => e
        logger.warn "ActiveMessaging: adapter #{adapter_name} not loaded: #{ e.message }"
      end
    end
  end

  def self.load_config
    path = File.expand_path("#{app_root}/config/messaging.rb")
    begin
      load path
    rescue MissingSourceFile
      logger.error "ActiveMessaging: no '#{path}' file to load"
    rescue
      raise $!, " ActiveMessaging: problems trying to load '#{path}': \n\t#{$!.message}"
    end
  end

  def self.load_processors(first=true)
    logger.info "ActiveMessaging: Loading #{app_root}/app/processors/application.rb" if first
    load "#{app_root}/app/processors/application.rb" if File.exist?("#{app_root}/app/processors/application.rb")
    Dir["#{app_root}/app/processors/*.rb"].each do |f|
      unless f.match(/\/application.rb/)
        logger.info "ActiveMessaging: Loading #{f}" if first
        load f
      end
    end
  end

  def self.reload_activemessaging
    # this is resetting the messaging.rb
    ActiveMessaging::Gateway.filters = []
    ActiveMessaging::Gateway.named_destinations = {}
    ActiveMessaging::Gateway.processor_groups = {}

    # now load the config
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
      err_msg = <<-EOM

      ActiveMessaging Error: No subscriptions.
      
      If you have no processor classes in app/processors, add them using the command:
        script/generate processor DoSomething"

      If you have processor classes, make sure they include in the class a call to 'subscribes_to':
        class DoSomethingProcessor < ActiveMessaging::Processor
          subscribes_to :do_something
          # ...
        end

      EOM
      puts err_msg
      logger.error err_msg
      exit
    end

    Gateway.start
  end

end

if !defined?(Rails::Railtie)
  ActiveMessaging.load_activemessaging
end
