require File.dirname(__FILE__) + '/test_helper'
require 'activemessaging/adapters/stomp'

loaded = true
begin
  require 'stomp'
rescue Object => e
  loaded = false
end
if loaded #only run these test if stomp gem installed


class FakeTCPSocket
  attr_accessor :sent_messages
  def initialize; @sent_messages=[]; end
  def puts(s=""); @sent_messages << s; end
  def write(s=""); self.puts s; end
  def ready?; true; end
end


module Stomp
  class Connection
    
    attr_accessor :subscriptions
    
    def socket
      @socket = FakeTCPSocket.new if @socket.nil?
      @socket
    end
    
    def receive=(msg)
      # stomp 1.0.5 code, now no longer works
      # sm = Stomp::Message.new do |m|
      #   m.command = 'MESSAGE'
      #   m.body = msg
      #   m.headers = {'message-id'=>'testmessage1', 'content-length'=>msg.length, 'destination'=>'destination1'}
      # end
      
      sm = Stomp::Message.new("MESSAGE\ndestination:/queue/stomp/destination/1\nmessage-id: messageid1\ncontent-length:#{msg.length}\n\n#{msg}\0\n")
      
      sm.command = 'MESSAGE'
      sm.headers = {'message-id'=>'testmessage1', 'content-length'=>msg.length, 'destination'=>'destination1'}
      
      @test_message = ActiveMessaging::Adapters::Stomp::Message.new(sm)
    end
    
    def receive
      @test_message
    end
  end
end

class StompTest < Test::Unit::TestCase

  def setup
    @connection = ActiveMessaging::Adapters::Stomp::Connection.new({})
    @d = "/queue/stomp/destination/1"
    @message = "mary had a little lamb"
    @connection.stomp_connection.receive = @message
  end

  def test_initialize
    i = { :retryMax => 4, 
          :deadLetterQueue=>'/queue/dlq',
          :login=>"",
          :passcode=> "",
          :host=> "localhost",
          :port=> "61613",
          :reliable=>FALSE,
          :reconnectDelay=> 5,
          :clientId=> 'cid' }

    @connection = ActiveMessaging::Adapters::Stomp::Connection.new(i)
    assert_equal 4, @connection.retryMax
    assert_equal '/queue/dlq', @connection.deadLetterQueue
  end

  def test_disconnect
    @connection.disconnect
    assert_equal "DISCONNECT", @connection.stomp_connection.socket.sent_messages[0]
  end

  def test_subscribe
    @connection.subscribe @d, {}
    assert_equal "SUBSCRIBE", @connection.stomp_connection.socket.sent_messages[0]
    # assert_equal "content-length:0", @connection.stomp_connection.socket.sent_messages[1]
    assert_equal "destination:#{@d}", @connection.stomp_connection.socket.sent_messages[1]
    assert_equal 1, @connection.stomp_connection.subscriptions.count
    assert_equal({'content-length'=>'0', :destination=>@d}, @connection.stomp_connection.subscriptions[@d])
  end

  def test_unsubscribe
    @connection.subscribe @d, {}
    @connection.stomp_connection.socket.sent_messages = []
    @connection.unsubscribe @d, {}
    assert_equal "UNSUBSCRIBE", @connection.stomp_connection.socket.sent_messages[0]
    # assert_equal "content-length:0", @connection.stomp_connection.socket.sent_messages[1]
    assert_equal "destination:#{@d}", @connection.stomp_connection.socket.sent_messages[1]
    assert_equal 0, @connection.stomp_connection.subscriptions.count
  end
  
  def test_send
    @connection.send(@d, @message, {})
    assert_equal 'SEND', @connection.stomp_connection.socket.sent_messages[0]
    # assert_equal "content-length:#{@message.length}", @connection.stomp_connection.socket.sent_messages[1]
    assert_equal "destination:#{@d}", @connection.stomp_connection.socket.sent_messages[1]
    assert_equal @message, @connection.stomp_connection.socket.sent_messages[5]
  end

  def test_receive
    m = @connection.receive
    assert_equal @message, m.body
  end
  
  def test_received
    m = @connection.receive
    m.headers[:transaction] = 'test-transaction'
    @connection.received m, {:ack=>'client'}
  end
  
  def test_unreceive
    @connection = ActiveMessaging::Adapters::Stomp::Connection.new({:retryMax=>4, :deadLetterQueue=>'/queue/dlq'})
    @connection.stomp_connection.receive = @message
    m = @connection.receive
    @connection.unreceive m, {:ack=>'client'}
  end

end

end # if loaded
