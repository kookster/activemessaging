#Adapter to rubigen / rails

if defined?(Rails)
  class NamedBase < Rails::Generator::NamedBase
  end
else
  class NamedBase < RubiGen::Base
    attr_reader   :name, :class_name, :singular_name, :plural_name
    attr_reader   :class_path, :file_path, :class_nesting, :class_nesting_depth
    alias_method :file_name, :singular_name
    alias_method :actions, :args
  
    def initialize(runtime_args, runtime_options={})
      super
    
      base_name = self.args.first
      assign_names!(base_name)
    end
  
    protected
  
    def assign_names!(name)
      @name = name
      base_name, @class_path, @file_path, @class_nesting, @class_nesting_depth = extract_modules(@name)
      @class_name_without_nesting, @singular_name, @plural_name = inflect_names(base_name)
      if @class_nesting.empty?
        @class_name = @class_name_without_nesting
      else
        @table_name = @class_nesting.underscore << "_" << @table_name
        @class_name = "#{@class_nesting}::#{@class_name_without_nesting}"
      end
    end

    # Extract modules from filesystem-style or ruby-style path:
    #   good/fun/stuff
    #   Good::Fun::Stuff
    # produce the same results.
    def extract_modules(name)
      modules = name.include?('/') ? name.split('/') : name.split('::')
      name    = modules.pop
      path    = modules.map { |m| m.underscore }
      file_path = (path + [name.underscore]).join('/')
      nesting = modules.map { |m| m.camelize }.join('::')
      [name, path, file_path, nesting, modules.size]
    end

    def inflect_names(name)
      camel  = name.camelize
      under  = camel.underscore
      plural = under.pluralize
      [camel, under, plural]
    end
  end
end