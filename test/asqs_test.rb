require File.dirname(__FILE__) + '/test_helper'

class AsqsTest < Test::Unit::TestCase
  
  class FakeHTTPResponse
    attr_accessor :headers, :body
    
    def to_hash
      @headers
    end
    
    def kind_of? kind
      true
    end
  end
  
  ActiveMessaging::Adapters::AmazonSQS::Connection.class_eval do
    attr_accessor :test_response, :test_headers

    DEFAULT_RESPONSE = <<EOM 
    <ListQueuesResponse xmlns='http://queue.amazonaws.com/doc/2007-05-01/' xmlns:xsi='http://www.w3.org/2001/XMLSchema-instance' xsi:type='ListQueuesResponse'>
    <Queues>
    <QueueUrl>http://queue.amazonaws.com/thisisatestid1/test1</QueueUrl>
    <QueueUrl>http://queue.amazonaws.com/thisisatestid12/test2</QueueUrl>
    </Queues>
    <ResponseStatus><StatusCode>Success</StatusCode><RequestId>cb919c0a-9bce-4afe-9b48-9bdf2412bb67</RequestId></ResponseStatus>
    </ListQueuesResponse>
EOM

    def http_request h, p, r
      raise test_response if test_response.is_a?(Exception)
      
      resp = FakeHTTPResponse.new
      resp.body = @test_response || DEFAULT_RESPONSE
      resp.headers = @test_headers || {}
      return resp
    end
  end
  

  def setup
    @connection = ActiveMessaging::Adapters::AmazonSQS::Connection.new(:reliable=>false, :access_key_id=>'access_key_id', :secret_access_key=>'secret_access_key', :reconnectDelay=>1)
    @d = "asqs"
    @message = "mary had a little lamb"
  end

  def teardown
    @connection.disconnect unless @connection.nil?
  end

  def test_allow_underscore_and_dash
    assert_nothing_raised do
      @connection.subscribe 'name-name_dash'
    end
    assert_raise(RuntimeError) do
      @connection.subscribe '!@#$%^&'
    end
  end

  
  def test_send_and_receive
    @connection.subscribe @d, :visibility_timeout=>100
    @connection.send @d, @message

    @connection.test_headers = {:destination=>@d}
    @connection.test_response = <<EOM
    <ReceiveMessageResponse>
      <Message>
        <MessageId>11YEJMCHE2DM483NGN40|3H4AA8J7EJKM0DQZR7E1|PT6DRTB278S4MNY77NJ0</MessageId>
        <ReceiptHandle>some handle value</ReceiptHandle>
        <Body>#{@message}</Body>
        <MD5OfBody>not really the md5</MD5OfBody>
      </Message>
      <ResponseStatus>
        <StatusCode>Success</StatusCode>
        <RequestId>b5bf2332-e983-4d3e-941a-f64c0d21f00f</RequestId>
      </ResponseStatus>
    </ReceiveMessageResponse>
EOM

    message = @connection.receive
    assert_equal @message, message.body
  end
  
  def test_receive_timeout
    @connection.subscribe @d
    @connection.send @d, @message

    @connection.test_headers = {:destination=>@d}
    @connection.test_response = TimeoutError.new('test timeout error')
    @connection.reliable = true
    begin
      Timeout.timeout 2 do
        @connection.receive
      end
    rescue Timeout::Error=>toe
      assert_not_equal toe.message, 'test timeout error'
    end
  end
  
end
