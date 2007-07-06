class A13gTestHarnessGenerator < Rails::Generator::Base
  def manifest
    record do |m|

      controller_path = 'app/controllers'
      m.directory controller_path
      m.file 'active_messaging_test_controller.rb', File.join(controller_path, 'active_messaging_test_controller.rb')

      view_path = 'app/views/active_messaging_test'
      m.directory view_path
      m.file 'index.rhtml', File.join(view_path, 'index.rhtml')

      view_path = 'app/views/layouts'
      m.directory view_path
      m.file 'active_messaging_test.rhtml', File.join(view_path, 'active_messaging_test.rhtml')

    end
  end
end
