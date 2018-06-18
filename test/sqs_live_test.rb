require File.dirname(__FILE__) + '/test_helper'
require 'activemessaging/adapters/sqs'

# only test if aws credentials provided
if ENV['AWS_ACCESS_KEY'] && ENV['AWS_SECRET_KEY']

  class SqsLiveTest < Test::Unit::TestCase
    def setup
      @connection = ActiveMessaging::Adapters::Sqs::Connection.new(
        :reliable => false,
        :access_key_id => ENV['AWS_ACCESS_KEY'],
        :secret_access_key => ENV['AWS_SECRET_KEY'],
        :reconnectDelay => 1)
      @test_queue_name = ENV['SQS_TEST_QUEUE']
    end

    def test_connection
      assert_not_nil @connection
      assert_not_nil @connection.cache_queue_list
    end

    def test_list_queues
      qs = @connection.list_queues(@test_queue_name)
      assert_equal 1, qs.size
    end

    def test_create_delete_queue
      n = rand(1000)
      qn = 'a13gtest_' + @test_queue_name + n.to_s
      q = @connection.create_queue(qn)
      assert_not_nil q
      resp = @connection.delete_queue(q)
    end

    def test_get_queue_attributes
      q = @connection.queues[@test_queue_name]
      attrs = @connection.get_queue_attributes(q)
      assert_equal 11, attrs.keys.size
    end

    def test_set_queue_attributes
      secs = rand(5)
      q = @connection.queues[@test_queue_name]
      response = @connection.set_queue_attributes(q, { 'DelaySeconds' => secs })
      attrs = @connection.get_queue_attributes(q, ['DelaySeconds'])
      assert_equal secs, attrs['DelaySeconds'].to_i
    end

    def test_send_messsage_json
      m = { 'bunny' => 'foo foo', 'when' => Time.now, 'num' => 20 }
      q = @connection.queues[@test_queue_name]
      response = @connection.send_messsage(q, m.to_json)
      assert_not_nil response

      response = @connection.send_messsage(q, m.to_yaml)
      assert_not_nil response
    end

    def test_send_messsage_special_chars
      m = { 'message' => 'specials !@#$%^&*()-_=+;:\'"\\/?,.<>', 'when' => Time.now, 'num' => 20 }
      q = @connection.queues[@test_queue_name]
      response = @connection.send_messsage(q, m.to_json)
      assert_not_nil response

      response = @connection.send_messsage(q, m.to_yaml)
      assert_not_nil response
    end

    def test_retrieve_messsages
      q = @connection.queues[@test_queue_name]
      messages = @connection.retrieve_messsages(q)
      assert_not_nil messages
      assert_equal 1, messages.size
      # puts messages.inspect
    end

    def test_delete_messsage
      q = @connection.queues[@test_queue_name]
      messages = @connection.retrieve_messsages(q)
      resp = @connection.delete_message(messages.first)
      assert_equal '200', resp.http_response.code
    end
  end

end # only test if aws credentials provided
