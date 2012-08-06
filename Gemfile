source "http://rubygems.org"

# We group everything into test because while a default bundle install
# pulls in this group, Jeweler does not include it when consulting the
# Gemfile for dependencies.
# The short syntax isn't used because the appraisal gem does not support it.
gem 'reliable-msg', '~>1.1', :group => :test, :platform => :ruby if RUBY_VERSION < '1.9'
gem 'jruby-activemq', :group => :test, :platform => :jruby
gem 'appraisal', :group => :test

gemspec :development_group => :test
