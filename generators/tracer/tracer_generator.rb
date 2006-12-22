class TracerGenerator < Rails::Generator::NamedBase
  def manifest
    record do |m|
      path = 'app/controllers'
      m.directory path
      m.template 'controller.rb', File.join(path, "#{file_name}_controller.rb")

      path = 'app/processors'
      m.directory path
      m.template 'trace_processor.rb', File.join(path, "#{file_name}_processor.rb")

      path = 'app/helpers'
      m.directory path
      m.template 'helper.rb', File.join(path, "#{file_name}_helper.rb")

      path = 'app/views/layouts'
      m.directory path
      m.file 'layout.rhtml', File.join(path, "#{file_name}.rhtml")

      path = "app/views/#{file_name}"
      m.directory path
      m.file 'index.rhtml', File.join(path, "index.rhtml")
    end
  end
end
