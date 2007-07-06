require File.dirname(__FILE__) + '/test_helper'

class FilterTest < Test::Unit::TestCase
  
  class MockFilter
    include Test::Unit::Assertions
    
    attr_reader :name
    
    def initialize(name)
      @name = name
    end
    
    def process(message, details={})
      @was_called = true
      @details=details
      yield
    end

    def assert_was_called
      assert @was_called, "#{name} should have been called"
      #@was_called = false
    end
    
    def assert_was_not_called
      assert !@was_called, "#{name} should not have been called"
    end

    def assert_routing expected
      assert_equal expected, @details
    end
  end

  class TestProcessor < ActiveMessaging::Processor
    include ActiveMessaging::MessageSender
    #subscribes_to :testqueue
    
    @@was_called = false
    class<<self
      include Test::Unit::Assertions
      
      def assert_was_called
        assert @@was_called
        @@was_called = false
      end
    end
    
    def on_message(message)
      @@was_called = true
    end
  end
  include ActiveMessaging::TestHelper
  def setup
    ActiveMessaging::Gateway.define do |d|
      d.queue :testqueue, 'testqueue'
      d.filter MockFilter.new(:bidirectional)
      d.filter MockFilter.new(:incoming), :direction => :in
      d.filter MockFilter.new(:outgoing), :direction => :out
    end
    
    TestProcessor.subscribes_to :testqueue
    
    @bidirectional, @incoming, @outgoing = ActiveMessaging::Gateway.filters.map {|f,o| f }
    
    # just checking we got the right filters
    assert_equal :bidirectional, @bidirectional.name
    assert_equal :incoming, @incoming.name
    assert_equal :outgoing, @outgoing.name
  end

  def teardown
    ActiveMessaging::Gateway.reset
  end

  def test_filters_and_processor_gets_called_on_receive
    ActiveMessaging::Gateway.dispatch ActiveMessaging::TestMessage.new('testqueue')
    @bidirectional.assert_was_called
    @incoming.assert_was_called
    @outgoing.assert_was_not_called
    TestProcessor.assert_was_called
  end
  
  def test_filters_gets_called_on_publish
    ActiveMessaging::Gateway.publish :testqueue, "blah blah"
    @bidirectional.assert_was_called
    @incoming.assert_was_not_called
    @outgoing.assert_was_called
  end

  def test_sets_routing_details_on_send
    sender = TestProcessor.new
    sender.publish :testqueue, "Hi there!"

    @outgoing.assert_was_called
    @outgoing.assert_routing({:destination=>ActiveMessaging::Gateway.find_queue(:testqueue), :publisher=>FilterTest::TestProcessor, :direction=>:outgoing})
  end

  def test_sets_routing_details_on_receive
    ActiveMessaging::Gateway.dispatch ActiveMessaging::TestMessage.new('testqueue')

    @incoming.assert_was_called
    @incoming.assert_routing({:destination=>ActiveMessaging::Gateway.find_queue(:testqueue), :receiver=>FilterTest::TestProcessor, :direction=>:incoming})
  end

  
end