require File.dirname(__FILE__) + '/test_helper'
require 'activemessaging/adapters/sqs'

class SqsTest < Test::Unit::TestCase

  LIST_QUEUES = <<-EOM
    <?xml version=\"1.0\"?>
    <ListQueuesResponse xmlns=\"http://queue.amazonaws.com/doc/2012-11-05/\">
      <ListQueuesResult>
        <QueueUrl>http://sqs.us-east-1.amazonaws.com/123456789012/test1</QueueUrl>
        <QueueUrl>http://sqs.us-east-1.amazonaws.com/123456789012/test2</QueueUrl>
      </ListQueuesResult>
      <ResponseMetadata>
        <RequestId>11122333-97f4-5d25-9bf0-c96fd56d0059</RequestId>
      </ResponseMetadata>
    </ListQueuesResponse>
  EOM

  class FakeHTTPResponse
    attr_accessor :headers, :body, :message_type

    def to_hash
      @headers
    end

    def kind_of? kind
      true
    end
  end

  class FakeSqsConnection < ActiveMessaging::Adapters::Sqs::Connection
    attr_accessor :test_responses

    def test_responses
      @test_responses ||= []
    end

    def http_request h, p, r
      test_response = test_responses.try(:pop)
      raise test_response if test_response.is_a?(Exception)
      resp = FakeHTTPResponse.new
      resp.body = test_response || LIST_QUEUES
      # resp.headers = @test_headers || {}
      return resp
    end
  end

  def setup
    @connection = FakeSqsConnection.new(
      :reliable => false,
      :access_key_id => 'access_key_id',
      :secret_access_key => 'secret_access_key',
      :reconnectDelay => 1
    )
    @d = 'test1'
    @message = 'mary had a little lamb'
  end

  def teardown
    @connection.disconnect unless @connection.nil?
  end

  def test_message_size
    assert_equal @connection.max_message_size, 8

    @connection = FakeSqsConnection.new(
      :reliable => false,
      :access_key_id => 'access_key_id',
      :secret_access_key => 'secret_access_key',
      :reconnectDelay => 1,
      :max_message_size => 10
    )

    assert_nothing_raised do
      @connection.send @d, @message
    end

    large_message = 'm' * 1024 * 9
    assert_nothing_raised do
      @connection.send @d, large_message
    end
    large_message = nil

    large_message = 'm' * 1024 * 11
    assert_raise(RuntimeError) do
      @connection.send @d, large_message
    end
    large_message = nil
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
    @connection.subscribe @d, :visibility_timeout => 100
    @connection.send @d, @message

    # @connection.test_headers = {:destination=>@d}
    @connection.test_responses.push <<-EOM
      <?xml version=\"1.0\"?>
      <ReceiveMessageResponse xmlns=\"http://queue.amazonaws.com/doc/2012-11-05/\">
        <ReceiveMessageResult>
          <Message>
            <MessageId>97af7709-d0f4-4b28-b728-8c144cb5f2b1</MessageId>
            <ReceiptHandle>ABC123DrLaLlB/NrnxsEYL90NypaOyBS2DVjinQ/f+nZjRv2pu8kZ/cp7mh822vMwzdlq9/IuQyr/XlIb5Mszn/qg0L+9/gAVRr4PqUXnqGijmMGw1hbL2oMOJgX620KpXeP3KdtquXbeu5A5s/3fcEO9KS82uJYLCq0Q+4uGfSwdmS9sttmRJDRN7qo+VZhHC3kzWayQotqE1mtmrbxUaAmg7qZb27u0cOHDMfLlzOWPGwiVAj+D+r8kZFEFo1Ljl+Ea+oJvvRNJSdvUuxw9Vu4x7sjA7Kw26TA5VxHFcXMVeHXZqfMcsMoltYgiK8IBza+Fi10/+DFIsQuMLwHX52duPkHqGKha2xP+tHAE0fF/p+NLwJ4MSW5TR0DEgwbR2FzxxctEUqH2KzbwDQcv3ZasA==</ReceiptHandle>
            <MD5OfBody>63a59149ccc2cc8b1c0cbc760ec18c03</MD5OfBody>
            <Body>#{@message}</Body>
            <Attribute>
              <Name>SenderId</Name>
              <Value>ABCDABCDABCDABCD12345</Value>
            </Attribute>
            <Attribute>
              <Name>ApproximateFirstReceiveTimestamp</Name>
              <Value>1528119384718</Value>
            </Attribute>
            <Attribute>
              <Name>ApproximateReceiveCount</Name>
              <Value>1</Value>
            </Attribute>
            <Attribute>
              <Name>SentTimestamp</Name>
              <Value>1527969505868</Value>
            </Attribute>
          </Message>
        </ReceiveMessageResult>
        <ResponseMetadata>
          <RequestId>12334556-1e57-5b04-a979-d2ba5ccfab7f</RequestId>
        </ResponseMetadata>
      </ReceiveMessageResponse>
    EOM

    message = @connection.receive
    assert_equal @message, message.body
  end

  def test_receive_timeout
    @connection.subscribe @d
    @connection.send @d, @message

    @connection.test_responses.push TimeoutError.new('test timeout error')
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
