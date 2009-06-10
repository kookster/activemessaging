ENV['APP_ENV'] = 'test'
APP_ENV = 'test'
if defined? Rails
  APP_ROOT = RAILS_ROOT
  require File.expand_path(File.dirname(__FILE__) + "/../../../../config/environment")
else
  APP_ROOT = File.dirname(__FILE__) + '/app'
  require 'rubygems'
  require 'activesupport'
  require File.dirname(__FILE__) + '/../lib/activemessaging/message_sender'
  require File.dirname(__FILE__) + '/../lib/activemessaging/processor'
  require File.dirname(__FILE__) + '/../lib/activemessaging/gateway'
end

# load other libraries
require 'test/unit'

require File.dirname(__FILE__) + '/../lib/activemessaging/test_helper'
require 'activemessaging/adapters/test'
