require File.dirname(__FILE__) + '/test_helper'

if defined?(JRUBY_VERSION)

class JmsTest < Test::Unit::TestCase

  def setup
    @test_txt = 'Yo Homie!'
    @isolation_const = rand(99999999)
    @connection = ActiveMessaging::Adapters::Jms::Connection.new(:url => 'tcp://localhost:61616',
      :login => '', 
      :passcode => '', 
      :connection_factory => 'org.apache.activemq.ActiveMQConnectionFactory')
  end
  
  def test_send
    @connection.send "/queue/TestQueue#{@isolation_const}", @test_txt, {}
  end
  
  def test_receive_with_one
    @connection.send "/queue/TestQueue#{@isolation_const}", @test_txt
    @connection.subscribe "/queue/TestQueue#{@isolation_const}"
    message = @connection.receive
    assert_equal @test_txt, message.body
  end
  
  def test_receive_multi
    10.times do |i|
      @connection.send "/queue/MultiQueue#{@isolation_const}", @test_txt
    end
    
    counter=0
    @connection.subscribe "/queue/MultiQueue#{@isolation_const}"
    while message = @connection.receive
      assert_equal @test_txt, message.body
      counter += 1
    end
    assert_equal 10, counter
  end
  
  def test_one_off_receive
    @connection.send "/queue/OneOff#{@isolation_const}", "one off message"
    message = @connection.receive "/queue/OneOff#{@isolation_const}"
    assert_equal "one off message", message.body
    assert_equal "MESSAGE", message.command
    assert_equal "/queue/OneOff#{@isolation_const}", message.headers['destination']
  end
  
  def test_unsubscribe
    @connection.subscribe "/queue/TestSubQueue#{@isolation_const}"
    @connection.unsubscribe "/queue/TestSubQueue#{@isolation_const}"
    assert_nil @connection.consumers["TestSubQueue#{@isolation_const}"]
  end
  
  def teardown
    @connection.close unless @connection.nil?
  end
  
end

end