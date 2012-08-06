source "http://rubygems.org"

# We group everything into test because while a default bundle install
# pulls in this group, Jeweler does not include it when consulting the
# Gemfile for dependencies.
group :test do
  gem 'reliable-msg', '~>1.1', :platform => :ruby if RUBY_VERSION < '1.9'
  gem 'jruby-activemq', :platform => :jruby
  gem 'appraisal'
end

gemspec :development_group => :test
