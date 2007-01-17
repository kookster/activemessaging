class ProcessorGenerator < Rails::Generator::NamedBase
  def manifest
    record do |m|
      path = 'app/processors'
      m.directory path
      m.template 'application.rb', File.join(path, "application.rb")
      m.template 'processor.rb', File.join(path, "#{file_name}_processor.rb")
      m.template 'messaging.rb', File.join('config', "messaging.rb")
    end
  end
end
