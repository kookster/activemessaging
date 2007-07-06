require File.dirname(__FILE__) + '/test_helper'

loaded = true
begin
  require 'reliable-msg'
rescue Object => e
  loaded = false
end
if loaded 

class ReliableMsgTest < Test::Unit::TestCase

  def setup
    @qm = ReliableMsg::QueueManager.new
    @qm.start
    @connection = ActiveMessaging::Adapters::ReliableMsg::Connection.new(:reliable=>false)
    @d = "/queue/reliable.msg.test.#{name()}."
    @message = "mary had a little lamb"
  end

  def teardown
    @connection.disconnect unless @connection.nil?
    @qm.stop unless @qm.nil?
  end
  
  def test_subscribe_and_unsubscribe
    assert_nil @connection.subscriptions["#{@d}test_subscribe"]
    @connection.subscribe "#{@d}test_subscribe"
    assert_equal 1, @connection.subscriptions["#{@d}test_subscribe"]
    @connection.subscribe "#{@d}test_subscribe"
    assert_equal 2, @connection.subscriptions["#{@d}test_subscribe"]
    @connection.unsubscribe "#{@d}test_subscribe"
    assert_equal 1, @connection.subscriptions["#{@d}test_subscribe"]
    @connection.unsubscribe "#{@d}test_subscribe"
    assert_nil @connection.subscriptions["#{@d}test_subscribe"]
  end

  def test_send_and_receive
    @connection.subscribe "#{@d}test_send_and_receive"
    @connection.send "#{@d}test_send_and_receive", @message 
    message = @connection.receive
    assert_equal @message, message.body
  end
  
end

end # if loaded