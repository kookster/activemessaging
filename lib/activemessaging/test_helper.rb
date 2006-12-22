require 'test/unit'
puts "#{File.dirname(__FILE__)}/trace_filter"
require "#{File.dirname(__FILE__)}/trace_filter"

module ActiveMessaging #:nodoc:

  class MockConnection
    attr_reader :sent

    def initialize
      reset!
    end

    def send queue, message, headers = {}
      @sent << [queue, message, headers]
    end
    
    def reset!
      @sent = []
    end

  end

  def ActiveMessaging.connection  
    @@connection = MockConnection.new unless defined?(@@connection)
    @@connection
  end

  def ActiveMessaging.sent
    @@connection = MockConnection.new unless defined?(@@connection)
    @@connection.sent
  end

  class Gateway
    def self.find_queue q
      q
    end

    def self.reset
      @@filters = []
      @@subscriptions = []
      @@named_queues = {}
      @@trace_on = nil
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

      def expect_message q, message, headers={}
        @expected_messages = [] if @expected_messages.nil?
        @expected_messages << [q, message, headers]
      end

      def verify_messages
        raise "You must set up some expected messages before calling verify_messages" if @expected_messages.nil?
        @expected_messages.each do |m|
          error_message = <<-"end_assert_message"
          Expected message #{m} was not received.
          Received messages:
          [#{ActiveMessaging.sent.join('/')}]
          end_assert_message
          assert ActiveMessaging.sent.member?(m), error_message 
        end
      end

      def verify_only_expected_messages
        raise "You must set up some expected messages before calling verify_messages" if @expected_messages.nil?
        @expected_messages.each do |m|
          error_message = <<-"end_assert_message"
          Expected message #{m} was not received.
          Received messages:
          [#{ActiveMessaging.sent.join('/')}]
          end_assert_message
          assert ActiveMessaging.sent.member?(m), error_message
          ActiveMessaging.sent.delete m
        end
        
        assert_equal [], ActiveMessaging.sent
      end

      def verify_no_messages
        if ActiveMessaging.sent !=[] then
          error_message = <<-"end_assert_message"
          Expected no messages.
          Received messages:
          [#{ActiveMessaging.sent.join('/')}]
          end_assert_message
          fail error_message
        end
      end

    end
  end
end

