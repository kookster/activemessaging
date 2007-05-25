class ProcessorGenerator < Rails::Generator::NamedBase
  def manifest
    record do |m|
      path = 'app/processors'
      test_path = 'test/functional'
      m.directory path
      m.template 'processor.rb', File.join(path, "#{file_name}_processor.rb")
      m.template 'processor_test.rb', File.join(test_path, "#{file_name}_processor_test.rb")
      m.template 'messaging.rb', File.join('config', "messaging.rb")
      m.file 'broker.yml', File.join('config', "broker.yml")
      m.file 'application.rb', File.join(path, "application.rb")
      m.file 'poller', File.join('script', "poller"), { :chmod => 0755 }
    end
  end
end
