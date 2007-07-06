require File.dirname(__FILE__) + '/test_helper'

class GatewayTest < Test::Unit::TestCase


  class TestProcessor < ActiveMessaging::Processor
    include ActiveMessaging::MessageSender
    #subscribes_to :testqueue
    def on_message(message)
      @test_message = true
    end
  end

  class TestAdapter
  end

  def setup
  end

  def teardown
    ActiveMessaging::Gateway.reset
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

  def test_dispatched
    ActiveMessaging::Gateway.destination :hello_world, '/queue/helloWorld'
    ActiveMessaging::Gateway.subscribe_to :hello_world, TestProcessor, headers={}
    sub = ActiveMessaging::Gateway.subscriptions.values.last
    dest = ActiveMessaging::Adapters::Test::Destination.new '/queue/helloWorld'
    msg = ActiveMessaging::Adapters::Test::Message.new({}, nil, "message_body", nil, dest)
    ActiveMessaging::Gateway.dispatched sub, msg
    assert_equal msg, ActiveMessaging::Gateway.connection.received_messages.first
  end

  def test_receive
    ActiveMessaging::Gateway.destination :hello_world, '/queue/helloWorld'
    ActiveMessaging::Gateway.publish :hello_world, "test_publish body", self.class, headers={}, timeout=10
    msg = ActiveMessaging::Gateway.receive :hello_world, self.class, headers={}, timeout=10
    assert_not_nil ActiveMessaging::Gateway.connection.find_message('/queue/helloWorld', "test_publish body")
  end

  ## figure out how to test these better - start in a thread perhaps?
  # def test_start
  # end
  # 
  # def test_stop
  # end

end
