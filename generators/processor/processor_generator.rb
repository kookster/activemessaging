class ProcessorGenerator < Rails::Generator::NamedBase
  def manifest
    record do |m|
      path = 'app/processors'
      m.directory path
      m.template 'processor.rb', File.join(path, "#{file_name}_processor.rb")
      m.template 'messaging.rb', File.join('config', "messaging.rb")
      m.file 'application.rb', File.join(path, "application.rb")
      m.file 'poller', File.join('script', "poller"), { :chmod => 0755 }
    end
  end
end
