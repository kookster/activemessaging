require File.dirname(__FILE__) + '/test_helper'

class TestProcessor < ActiveMessaging::Processor
  subscribes_to :hello_world

  def on_message message
    #do nothing
  end
end

class TestSender < ActiveMessaging::Processor
  publishes_to :hello_world

end

class TracerTest < Test::Unit::TestCase

  def setup
    ActiveMessaging::Gateway.define do |s|
      s.queue :hello_world, '/queue/helloWorld'
      s.queue :trace, '/queue/trace'

      s.filter TraceFilter.new(:trace)
    end
    ActiveMessaging.connection.reset!
  end

  def test_should_trace_sent_messages
    message = "Ni hao ma?"

    expect_message :trace, "<sent><from>TestSender</from><queue>hello_world</queue><message>#{message}</message></sent>"
    expect_message :hello_world, message

    sender = TestSender.new
    sender.publish :hello_world, message

    verify_messages
  end

  class FakeMessage
    def command
      'MESSAGE'
    end
    def headers
      {'destination'=>:hello_world}
    end
    def body
      "Ni hao ma?"
    end
  end

  def test_should_trace_received_messages
    message = "Ni hao ma?"
    
    expect_message :trace, "<received><by>TestProcessor</by><queue>hello_world</queue><message>#{message}</message></received>"

    ActiveMessaging::Gateway.dispatch FakeMessage.new
    
    verify_messages
  end

  def tear_down
    puts 'calling'
    ActiveMessaging::Gateway.reset
  end
end