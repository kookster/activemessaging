module ActiveMessaging
  class ProcessorGenerator < Rails::Generators::NamedBase
    # namespace "activemessaging"
    source_root File.expand_path("../templates", __FILE__)

    # check_class_collision :suffix=>"Processor"
    
    def copy_processor
      template "processor.rb", "app/processors/#{file_name}_processor.rb"
    end
    
    def copy_messaging
      template "messaging.rb", "config/messaging.rb"
    end
    
    hook_for :test_framework, :as => :active_messaging_processor
    
  end
end

module TestUnit
  class ActiveMessagingProcessor < Rails::Generators::NamedBase
    source_root File.expand_path("../templates", __FILE__)
    
    def copy_processor
      template "processor_test.rb", "test/functional/#{file_name}_processor_test.rb"
    end
  end
end

module Rspec
  class ActiveMessagingProcessor < Rails::Generators::NamedBase
    source_root File.expand_path("../templates", __FILE__)
    
    def copy_processor
      template "processor_spec.rb", "spec/functional/#{file_name}_processor_spec.rb"
    end
  end
end