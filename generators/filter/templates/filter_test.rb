require File.dirname(__FILE__) + '/../test_helper'
require File.dirname(__FILE__) + '/../../vendor/plugins/activemessaging/lib/activemessaging/test_helper'

class <%= class_name %>FilterTest < Test::Unit::TestCase
  include ActiveMessaging::TestHelper
  
  def setup
    # if you want to write code to tests against the filter directly
    load File.dirname(__FILE__) + "/../../app/processors/<%= file_name %>_filter.rb"
    @options = {:direction=>:incoming, :only=>:<%= file_name %>_test}
    @filter = <%= class_name %>Filter.new(@options)
    @destination = ActiveMessaging::Gateway.destination :<%= file_name %>_test, '/queue/<%= file_name %>.test.queue'
  end
  
  def teardown
    ActiveMessaging::Gateway.reset
    @filter = nil
    @destination = nil
    @options = nil
  end  

  def test_<%= file_name %>_filter
    @message = ActiveMessaging::TestMessage.new(@destination.value, {'message-id'=>'test-message-id-header'}, 'message body')
    @routing = {:direction=>:incoming, :destination=>@destination}
    @filter.process(@message, @routing)
  end

end