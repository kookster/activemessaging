module ActiveMessaging
  class InstallGenerator < Rails::Generators::Base
    source_root File.expand_path("../templates", __FILE__)
    
    argument :poller_name, :type => :string, :default => 'poller', :banner => 'poller_name'

    def copy_application
      copy_file "application_processor.rb", "app/processors/application_processor.rb"
    end
    
    def copy_poller
      template "poller", "script/#{poller_name}"
      chmod("script/#{poller_name}", 0755)
    end
    
    def copy_poller_rb
      copy_file "poller.rb", "lib/#{poller_name}.rb"
    end
    
    def copy_broker_rb
      copy_file "broker.yml", "config/broker.yml"
    end
    
    def add_gems
      gem("daemons")
    end
    
   
    def change_application
      application '  config.autoload_paths += %W(#{config.root}/app/processors)'
    end
    
  end
end