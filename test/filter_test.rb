require File.dirname(__FILE__) + '/test_helper'

module ActiveMessaging #:nodoc:
  def self.reload_activemessaging
  end
end

class FilterTest < Test::Unit::TestCase
  
  class MockFilter < ActiveMessaging::Filter
    
    @@called = {}
    cattr_reader :called

    attr_reader :options
    
    def initialize(options)
      @options = options
    end
    
    def process(message, details={})
      @@called[options[:name]] = {:message=>message, :details=>details}
    end
    
    class << self
      include Test::Unit::Assertions

      def reset
        @@called = {}
      end
      
      def assert_was_called(name=nil)
        assert @@called.has_key?(name)
      end

      def assert_was_not_called(name=nil)
        assert !@@called.has_key?(name)
      end

      def assert_routing(name, routing)
        assert_equal routing, @@called[name][:details]
      end
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
      d.destination :testqueue, '/queue/test.queue'
      d.filter 'filter_test/mock_filter', :direction=>:bidirectional, :name=>:bidirectional
      d.filter 'filter_test/mock_filter', :direction=>:incoming, :name=>:incoming
      d.filter 'filter_test/mock_filter', :direction=>:outgoing, :name=>:outgoing

      d.filter 'filter_test/mock_filter', :direction=>:incoming, :name=>:exclude_only, :only=>:foo
      d.filter 'filter_test/mock_filter', :direction=>:incoming, :name=>:include_only, :only=>:testqueue
      d.filter 'filter_test/mock_filter', :direction=>:incoming, :name=>:exclude_except, :except=>:testqueue
      d.filter 'filter_test/mock_filter', :direction=>:incoming, :name=>:include_except, :except=>:foo
    end
    
    TestProcessor.subscribes_to :testqueue
    MockFilter.reset
  end

  def teardown
    ActiveMessaging::Gateway.reset
  end

  def test_filters_use_include
    ActiveMessaging::Gateway.dispatch ActiveMessaging::TestMessage.new('/queue/test.queue')
    MockFilter.assert_was_called(:include_only)
    MockFilter.assert_was_not_called(:exclude_only)
  end

  def test_filters_use_exclude
    ActiveMessaging::Gateway.dispatch ActiveMessaging::TestMessage.new('/queue/test.queue')
    MockFilter.assert_was_called(:include_except)
    MockFilter.assert_was_not_called(:exclude_except)
  end

  def test_filters_and_processor_gets_called_on_receive
    ActiveMessaging::Gateway.dispatch ActiveMessaging::TestMessage.new('/queue/test.queue')
    MockFilter.assert_was_called(:bidirectional)
    MockFilter.assert_was_called(:incoming)
    MockFilter.assert_was_not_called(:outgoing)
    TestProcessor.assert_was_called
  end
  
  def test_filters_gets_called_on_publish
    ActiveMessaging::Gateway.publish :testqueue, "blah blah"
    MockFilter.assert_was_called(:bidirectional)
    MockFilter.assert_was_not_called(:incoming)
    MockFilter.assert_was_called(:outgoing)
  end

  def test_sets_routing_details_on_send
    sender = TestProcessor.new
    sender.publish :testqueue, "Hi there!"
  
    MockFilter.assert_was_called(:outgoing)
    MockFilter.assert_routing(:outgoing, {:destination=>ActiveMessaging::Gateway.find_queue(:testqueue), :publisher=>FilterTest::TestProcessor, :direction=>:outgoing})
  end
  
  def test_sets_routing_details_on_receive
    ActiveMessaging::Gateway.dispatch ActiveMessaging::TestMessage.new('/queue/test.queue')
  
    MockFilter.assert_was_called(:incoming)
    MockFilter.assert_routing(:incoming, {:destination=>ActiveMessaging::Gateway.find_queue(:testqueue), :receiver=>FilterTest::TestProcessor, :direction=>:incoming})
  end
  
end