require 'test/unit'
#require "#{File.dirname(__FILE__)}/trace_filter"


module ActiveMessaging #:nodoc:

  class Gateway
  
    def self.reset
      unsubscribe
      disconnect
      @@filters = []
      @@subscriptions = {}
      @@named_destinations = {}
      @@trace_on = nil
      @@processor_groups = {}
      @@current_processor_group = nil
      @@connections = {}
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

  module TestHelper
    
    #Many thanks must go to the fixture_caching plugin
    #for showing how to properly alias setup and teardown
    #from within the tyranny of the fixtures code
    def self.included(base)
      base.extend(ClassMethods)

      class << base
        alias_method_chain :method_added, :a13g_hack
      end
      
      base.class_eval do
        alias_method_chain :setup, :a13g
        alias_method_chain :teardown, :a13g
      end
    end
    
    module ClassMethods
      def method_added_with_a13g_hack method
        return if caller.first.match(/#{__FILE__}/)
        case method.to_sym
        when :setup
          @setup_method = instance_method(:setup)
          alias_method :setup, :setup_with_a13g
        when :teardown
          @teardown_method = instance_method(:teardown)
          alias_method :teardown, :teardown_with_a13g
        else
          method_added_without_a13g_hack(method)
        end
      end
      
      def setup_method
        @setup_method
      end
      
      def teardown_method
        @teardown_method
      end
    end
    
    def setup_with_a13g
      setup_without_a13g
      self.class.setup_method.bind(self).call unless self.class.setup_method.nil?
      ActiveMessaging.load_config
    end

    def teardown_with_a13g
      teardown_without_a13g
      self.class.teardown_method.bind(self).call unless self.class.teardown_method.nil?
      ActiveMessaging::Gateway.reset
    end

    def mock_publish destination, body, publisher=nil, headers={}
      ActiveMessaging::Gateway.publish destination, body, publisher, headers
    end

    def assert_message destination, body
      destination = ActiveMessaging::Gateway.find_destination(destination).value
      error_message = <<-EOF
      Message for '#{destination}' with '#{body}' is not present.
      Messages:
      #{ActiveMessaging::Gateway.connection('default').all_messages.inspect}
      EOF
      assert ActiveMessaging::Gateway.connection.find_message(destination, body), error_message
    end
      
    def assert_no_message_with destination, body
      destination = ActiveMessaging::Gateway.find_destination(destination).value
      error_message = <<-EOF
      Message for '#{destination}' with '#{body}' is present.
      Messages:
      #{ActiveMessaging::Gateway.connection('default').all_messages.inspect}
      EOF
      assert_nil ActiveMessaging::Gateway.connection('default').find_message(destination, body), error_message
    end

    def assert_no_messages destination
      destination = ActiveMessaging::Gateway.find_destination(destination).value
      error_message = <<-EOF
      Expected no messages.
      Messages:
      #{ActiveMessaging::Gateway.connection('default').all_messages.inspect}
      EOF
      assert_equal [], ActiveMessaging::Gateway.connection('default').all_messages, error_message
    end

    def assert_subscribed destination
      destination = ActiveMessaging::Gateway.find_destination(destination).value
      error_message = <<-EOF
      Not subscribed to #{destination}.
      Subscriptions:
      #{ActiveMessaging::Gateway.connection('default').subscriptions.inspect}
      EOF
      assert ActiveMessaging::Gateway.connection('default').find_subscription(destination), error_message
    end

    def assert_not_subscribed destination
      destination = ActiveMessaging::Gateway.find_destination(destination).value
      error_message = <<-EOF
      Subscribed to #{destination}.
      Subscriptions:
      #{ActiveMessaging::Gateway.connection('default').subscriptions.inspect}
      EOF
      assert_nil ActiveMessaging::Gateway.connection('default').find_subscription(destination), error_message
    end
    
    def assert_has_messages destination
      destination_name = ActiveMessaging::Gateway.find_destination(destination).value
      error_message = <<-EOF
      No messages for #{destination_name}.
      All messages:
      #{ActiveMessaging::Gateway.connection('default').all_messages.inspect}
      EOF
      destination = ActiveMessaging::Gateway.connection('default').find_destination destination_name
      assert !destination.nil? && !destination.messages.empty?, error_message
    end
  end
end

