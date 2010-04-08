rails_environtment_file = File.expand_path(File.dirname(__FILE__) + "/../../../../config/environment")

if File.exists? rails_environtment_file
  require rails_environment_file
  APP_ROOT = RAILS_ROOT
else
  ENV['APP_ENV'] = 'test'
  APP_ENV = 'test'
  
  $: << File.expand_path(File.dirname(__FILE__) + '/../lib')
  require 'rubygems'
  require 'active_support'
  require 'activemessaging/message_sender'
  require 'activemessaging/processor'
  require 'activemessaging/gateway'
  require 'activemessaging/filter'
  require 'activemessaging/adapters/test'
  APP_ROOT = File.dirname(__FILE__) + '/app'
end
  
# load other libraries
require 'test/unit'

require File.dirname(__FILE__) + '/../lib/activemessaging/test_helper'
