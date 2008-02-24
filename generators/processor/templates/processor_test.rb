require File.dirname(__FILE__) + '/../test_helper'
require File.dirname(__FILE__) + '/../../vendor/plugins/activemessaging/lib/activemessaging/test_helper'
require File.dirname(__FILE__) + '/../../app/processors/application'

class <%= class_name %>ProcessorTest < Test::Unit::TestCase
  include ActiveMessaging::TestHelper
  
  def setup
    @processor = <%= class_name %>Processor.new
  end
  
  def teardown
    @processor = nil
  end  

  def test_<%= file_name %>_processor
    @processor.on_message('Your test message here!')
  end
end