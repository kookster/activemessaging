# load the rails environment
# TODO currently requires you to run tests as a installed plugin, we should try to fix this
ENV['RAILS_ENV'] = "test"
require File.expand_path(File.dirname(__FILE__) + "/../../../../config/environment")

# load other libraries
require 'test/unit'

# load activemessaging
# TODO this is already loaded automatically by starting Rails
# but we may need to do this if we want to run a13g tests without Rails
#require File.dirname(__FILE__) + '/../lib/activemessaging/processor'
#require File.dirname(__FILE__) + '/../lib/activemessaging/gateway'
require File.dirname(__FILE__) + '/../lib/activemessaging/test_helper'


