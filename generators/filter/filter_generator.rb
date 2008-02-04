class FilterGenerator < Rails::Generator::NamedBase
  def manifest
    record do |m|
      path = 'app/processors'
      test_path = 'test/functional'

      # Check for class naming collisions
      m.class_collisions class_path, "#{class_name}Controller", "#{class_name}ControllerTest", "#{class_name}Helper"

      # filter and test directories
      m.directory File.join(path, class_path)
      m.directory File.join(test_path, class_path)

      # filter and test templates
      m.template 'filter.rb', File.join(path, class_path, "#{file_name}_filter.rb")
      m.template 'filter_test.rb', File.join(test_path, class_path, "#{file_name}_filter_test.rb")
    end
  end
end
