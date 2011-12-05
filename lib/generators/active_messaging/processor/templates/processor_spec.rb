require File.expand_path(File.dirname(__FILE__) + '/../spec_helper')
require 'activemessaging/test_helper'
require File.dirname(__FILE__) + '/../../app/processors/application_processor'

describe <%= class_name %>Processor do
  
  include ActiveMessaging::TestHelper
  
  before(:each) do
    load File.dirname(__FILE__) + "/../../app/processors/<%= file_name %>_processor.rb"
    @processor = <%= class_name %>Processor.new
  end
  
  after(:each) do
    @processor = nil
  end
  
  it "should receive message" do
    @processor.on_message('Your test message here!')
  end

  
  
end