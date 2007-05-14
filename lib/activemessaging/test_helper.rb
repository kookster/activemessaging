require 'test/unit'
puts "#{File.dirname(__FILE__)}/trace_filter"
require "#{File.dirname(__FILE__)}/trace_filter"

module ActiveMessaging #:nodoc:

  class Gateway
  
    def self.reset
      @@filters = []
      @@subscriptions = {}
      @@named_queues = {}
      @@trace_on = nil
      connection('default').disconnect
    end
    
  end
  
  class TestMessage
    attr_reader :headers
    attr_accessor :body

    def initialize(destination, headers = {}, body = "")
      @headers, @body = headers, body
      @headers['destination'] = destination
    end
    
    def command
      "MESSAGE"
    end
  end

end


module Test
  module Unit
    class TestCase #:nodoc:

      def assert_message queue, body
        queue = ActiveMessaging::Gateway.find_queue(queue).destination
        error_message = <<-"end_assert_message"
        Message for '#{queue}' with '#{body}' is not present.
        Messages:
        #{ActiveMessaging::Gateway.connection('default').all_messages.inspect}
        end_assert_message
        assert ActiveMessaging::Gateway.connection.find_message(queue, body), error_message
      end
      
      def assert_no_message queue, body
        queue = ActiveMessaging::Gateway.find_queue(queue).destination
        error_message = <<-"end_assert_message"
        Message for '#{queue}' with '#{body}' is present.
        Messages:
        #{ActiveMessaging::Gateway.connection('default').all_messages.inspect}
        end_assert_message
        assert_nil ActiveMessaging::Gateway.connection('default').find_message(queue, body), error_message
      end

      def assert_no_messages queue, body
        queue = ActiveMessaging::Gateway.find_queue(queue).destination
        error_message = <<-"end_assert_message"
        Expected no messages.
        Messages:
        #{ActiveMessaging::Gateway.connection('default').all_messages.inspect}
        end_assert_message
        assert_equal [], ActiveMessaging::Gateway.connection('default').all_messages, error_message
      end
      
      def assert_subscribed queue
        queue = ActiveMessaging::Gateway.find_queue(queue).destination
        error_message = <<-"end_assert_message"
        Not subscribed to #{queue}.
        Subscriptions:
        #{ActiveMessaging::Gateway.connection('default').subscriptions.inspect}
        end_assert_message
        assert ActiveMessaging::Gateway.connection('default').find_subscription(queue), error_message
      end
      
      def assert_not_subscribed queue
        queue = ActiveMessaging::Gateway.find_queue(queue).destination
        error_message = <<-"end_assert_message"
        Subscribed to #{queue}.
        Subscriptions:
        #{ActiveMessaging::Gateway.connection('default').subscriptions.inspect}
        end_assert_message
        assert_nil ActiveMessaging::Gateway.connection('default').find_subscription(queue), error_message
      end
      
      def assert_messages_for queue_name
        queue_name = ActiveMessaging::Gateway.find_queue(queue).destination
        error_message = <<-"end_assert_message"
        No messages for #{queue_name}.
        All messages:
        #{ActiveMessaging::Gateway.connection('default').all_messages.inspect}
        end_assert_message
        queue = ActiveMessaging::Gateway.connection('default').find_queue queue_name
        assert !queue.nil? && !queue.messages.empty?, error_message
      end
      
      def assert_no_messages_for queue_name
        queue_name = ActiveMessaging::Gateway.find_queue(queue).destination
        error_message = <<-"end_assert_message"
        #{queue_name} has messages.
        Messages in queue:
        #{ActiveMessaging::Gateway.connection('default').find_queue(queue_name).messages.inspect}
        end_assert_message
        queue = ActiveMessaging::Gateway.connection('default').find_queue queue_name
        assert queue.nil? || queue.messages.empty?, error_message
      end
    end
  end
end



