require 'test/unit'
#require "#{File.dirname(__FILE__)}/trace_filter"


module ActiveMessaging #:nodoc:

  # def self.reload_activemessaging
  # end

  class Gateway
    
    def self.reset
      unsubscribe
      disconnect
      @@filters = []
      @@subscriptions = {}
      @@named_destinations = {}
      @@processor_groups = {}
      @@current_processor_group = nil
      @@connections = {}
    end    
  end
  
  module MessageSender
    
    @@__a13g_initialized__ = false
    def publish_with_reset(destination_name, message, headers={}, timeout=10)
      unless @@__a13g_initialized__
        ActiveMessaging.reload_activemessaging 
        @@__a13g_initialized__ = true
      end
      publish_without_reset(destination_name, message, headers, timeout)
    end

    alias_method_chain :publish, :reset
    
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
    
    # #Many thanks must go to the ActiveRecord fixture code
    # #for showing how to properly alias setup and teardown
    # def self.included(base)
    #   base.extend(ClassMethods)
    # 
    #   class << base
    #     alias_method_chain :method_added, :a13g
    #   end
    #   
    # end
    
    # module ClassMethods
    # 
      # def method_added_with_a13g(method)
      #   return if @__a13g_disable_method_added__
      #   @__a13g_disable_method_added__ = true
      #   
      #   case method.to_s
      #   when 'setup'
      #     unless method_defined?(:setup_without_a13g)
      #       alias_method :setup_without_a13g, :setup
      #       define_method(:full_setup) do
      #         setup_with_a13g
      #         setup_without_a13g
      #       end
      #     end
      #     alias_method :setup, :full_setup
      #   when 'teardown'
      #     unless method_defined?(:teardown_without_a13g)
      #       alias_method :teardown_without_a13g, :teardown
      #       define_method(:full_teardown) do
      #         teardown_without_a13g
      #         teardown_with_a13g
      #       end
      #     end
      #     alias_method :teardown, :full_teardown
      #   end
      # 
      #   method_added_without_a13g(method)
      #   
      #   @__a13g_disable_method_added__ = false
      # end
    # 
    # end
    
    # def setup_with_a13g
    #   ActiveMessaging.reload_activemessaging
    # end
    # 
    # def teardown_with_a13g
    #   ActiveMessaging::Gateway.reset
    # end

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

