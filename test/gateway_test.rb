require File.dirname(__FILE__) + '/test_helper'

class InitializeFilter
  
  attr_accessor :options

  def initialize(options)
    @options = options
  end
  
  def process(message, details={})
    puts "ObjectFilter process called!"
  end
end

class GatewayTest < Test::Unit::TestCase


  class ClassFilter
    
    def initialize
      raise "Don't try and construct one of these please"
    end
    
    class << self
      def process(message, details={})
        puts "ClassFilter process called!"
      end
    end
  end

  class ObjectFilter
    def process(message, details={})
      puts "ObjectFilter process called!"
    end
  end

  class TestProcessor < ActiveMessaging::Processor
    include ActiveMessaging::MessageSender
    #subscribes_to :testqueue
    def on_message(message)
      @test_message = true
    end
  end

  class TestRetryProcessor < ActiveMessaging::Processor
    include ActiveMessaging::MessageSender
    #subscribes_to :testqueue
    def on_message(message)
      puts "TestRetryProcessor - about to raise exception"
      raise ActiveMessaging::AbortMessageException.new("Cause a retry!")
    end
  end

  class TestAdapter
  end

  def setup
  end

  def teardown
    ActiveMessaging::Gateway.reset
  end
  
  
  def test_create_filter
    filter_obj = ActiveMessaging::Gateway.create_filter('gateway_test/object_filter', {:direction=>:incoming, :name=>'test1'})
    assert filter_obj
    assert filter_obj.is_a?(GatewayTest::ObjectFilter)
    
    filter_obj = ActiveMessaging::Gateway.create_filter('initialize_filter', {:direction=>:incoming, :name=>'test2'})
    assert filter_obj
    assert filter_obj.is_a?(InitializeFilter)
    assert_equal filter_obj.options, {:direction=>:incoming, :name=>'test2'}
    
    filter_obj = ActiveMessaging::Gateway.create_filter(:initialize_filter, {:direction=>:incoming, :name=>'test2'})
    assert filter_obj
    assert filter_obj.is_a?(InitializeFilter)
    assert_equal filter_obj.options, {:direction=>:incoming, :name=>'test2'}

    filter_obj = ActiveMessaging::Gateway.create_filter(:'gateway_test/class_filter', {:direction=>:incoming, :name=>'test2'})
    assert filter_obj
    assert filter_obj.is_a?(Class)
    assert_equal filter_obj.name, "GatewayTest::ClassFilter"
  end
  
  def test_register_adapter 
    ActiveMessaging::Gateway.register_adapter :test_register_adapter, TestAdapter
    assert_equal TestAdapter, ActiveMessaging::Gateway.adapters[:test_register_adapter]
  end

  def test_destination
    ActiveMessaging::Gateway.destination :hello_world, '/queue/helloWorld'
    dest = ActiveMessaging::Gateway.named_destinations[:hello_world]
    assert_equal :hello_world, dest.name
  end

  def test_destination_duplicates
    ActiveMessaging::Gateway.destination :hello_world, '/queue/helloWorld'
    dest = ActiveMessaging::Gateway.named_destinations[:hello_world]
    assert_equal :hello_world, dest.name

    # make sure a dupe name causes an error
    assert_raises RuntimeError do 
      ActiveMessaging::Gateway.destination :hello_world, '/queue/helloWorld2'
    end
  end

  def test_connection
    conn = ActiveMessaging::Gateway.connection
    assert_equal conn.class, ActiveMessaging::Adapters::Test::Connection
  end

  def test_subscribe_and_unsubscribe
    ActiveMessaging::Gateway.destination :hello_world, '/queue/helloWorld'
    ActiveMessaging::Gateway.subscribe_to :hello_world, TestProcessor, headers={}
    sub = ActiveMessaging::Gateway.subscriptions.values.last
    assert_equal :hello_world, sub.destination.name
    assert_equal TestProcessor, sub.processor_class

    ActiveMessaging::Gateway.subscribe
    assert_not_nil ActiveMessaging::Gateway.connection.find_subscription(sub.destination.value)

    ActiveMessaging::Gateway.unsubscribe
    assert_nil ActiveMessaging::Gateway.connection.find_subscription(sub.destination.value)
  end

  def test_disconnect
    assert_equal 0, ActiveMessaging::Gateway.connections.keys.size

    conn = ActiveMessaging::Gateway.connection
    assert_equal 1, ActiveMessaging::Gateway.connections.keys.size
    assert_equal true, conn.connected

    ActiveMessaging::Gateway.disconnect

    assert_equal 0, ActiveMessaging::Gateway.connections.keys.size
    assert_equal false, conn.connected
  end

  def test_publish
    ActiveMessaging::Gateway.destination :hello_world, '/queue/helloWorld'
    ActiveMessaging::Gateway.publish :hello_world, "test_publish body", self.class, headers={}, timeout=10
    assert_not_nil ActiveMessaging::Gateway.connection.find_message('/queue/helloWorld', "test_publish body")
    
    assert_raise(RuntimeError) do
      ActiveMessaging::Gateway.publish :hello_world, nil, self.class, headers={}, timeout=10
    end
    assert_raise(RuntimeError) do
      ActiveMessaging::Gateway.publish :hello_world, '', self.class, headers={}, timeout=10
    end
  end

  def test_acknowledge_message
    ActiveMessaging::Gateway.destination :hello_world, '/queue/helloWorld'
    ActiveMessaging::Gateway.subscribe_to :hello_world, TestProcessor, headers={}
    sub = ActiveMessaging::Gateway.subscriptions.values.last
    dest = ActiveMessaging::Adapters::Test::Destination.new '/queue/helloWorld'
    msg = ActiveMessaging::Adapters::Test::Message.new({}, nil, "message_body", nil, dest)
    ActiveMessaging::Gateway.acknowledge_message sub, msg
    assert_equal msg, ActiveMessaging::Gateway.connection.received_messages.first
  end

  def test_abort_message
    ActiveMessaging::Gateway.destination :hello_world, '/queue/helloWorld'
    ActiveMessaging::Gateway.subscribe_to :hello_world, TestRetryProcessor, headers={}
    sub = ActiveMessaging::Gateway.subscriptions.values.last
    dest = ActiveMessaging::Adapters::Test::Destination.new '/queue/helloWorld'
    msg = ActiveMessaging::Adapters::Test::Message.new({}, nil, "message_body", nil, dest)
    ActiveMessaging::Gateway.dispatch(msg)
    assert_equal msg, ActiveMessaging::Gateway.connection.unreceived_messages.first
  end

  def test_receive
    ActiveMessaging::Gateway.destination :hello_world, '/queue/helloWorld'
    ActiveMessaging::Gateway.publish :hello_world, "test_publish body", self.class, headers={}, timeout=10
    msg = ActiveMessaging::Gateway.receive :hello_world, self.class, headers={}, timeout=10
    assert_not_nil ActiveMessaging::Gateway.connection.find_message('/queue/helloWorld', "test_publish body")
  end

  def test_reload
    ActiveMessaging.reload_activemessaging
    size = ActiveMessaging::Gateway.named_destinations.size
    ActiveMessaging.reload_activemessaging
    assert_equal size, ActiveMessaging::Gateway.named_destinations.size
  end

  ## figure out how to test these better - start in a thread perhaps?
  # def test_start
  # end
  # 
  # def test_stop
  # end

end
