require File.dirname(__FILE__) + '/test_helper'

class TestProcessor < ActiveMessaging::Processor
  #subscribes_to :hello_world

  def on_message message
    #do nothing
  end
end

class TestSender < ActiveMessaging::Processor
  #publishes_to :hello_world

end

class FakeMessage
  def command
    'MESSAGE'
  end
  def headers
    {'destination'=>'/queue/helloWorld'}
  end
  def body
    "Ni hao ma?"
  end
end

class TracerTest < Test::Unit::TestCase
  include ActiveMessaging::TestHelper
  def setup
    ActiveMessaging::Gateway.define do |s|
      s.queue :hello_world, '/queue/helloWorld'
      s.queue :trace, '/queue/trace'

      s.filter TraceFilter.new(:trace)
    end
    
    TestProcessor.subscribes_to :hello_world
    TestSender.publishes_to :hello_world
  end

  def teardown
    ActiveMessaging::Gateway.reset
  end

  def test_should_trace_sent_messages
    message = "Ni hao ma?"

    sender = TestSender.new
    sender.publish :hello_world, message

    assert_message :trace, "<sent><from>TestSender</from><queue>hello_world</queue><message>#{message}</message></sent>"
    assert_message :hello_world, message
  end

  def test_should_trace_received_messages
    message = "Ni hao ma?"

    ActiveMessaging::Gateway.dispatch FakeMessage.new

    assert_message :trace, "<received><by>TestProcessor</by><queue>hello_world</queue><message>#{message}</message></received>"
  end
end