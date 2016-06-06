source "https://rubygems.org"

# We group everything into test because while a default bundle install
# pulls in this group, Jeweler does not include it when consulting the
# Gemfile for dependencies.
# The short syntax isn't used because the appraisal gem does not support it.
require 'rubygems'
gem 'jruby-activemq', :group => :test, :platform => :jruby
gem 'appraisal', '~>2.1.0', :group => :test

gemspec :development_group => :test
