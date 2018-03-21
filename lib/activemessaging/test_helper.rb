module ActiveMessaging #:nodoc:
  @@logger = nil

  def self.logger
    @@logger ||= MockLogger.new
    @@logger
  end

  class AbortMessageException < Exception #:nodoc:
  end

  class StopFilterException < Exception #:nodoc:
  end

  class Gateway

    def self.reset
      unsubscribe
      disconnect
      @filters = []
      @subscriptions = {}
      @named_destinations = {}
      @processor_groups = {}
      @current_processor_group = nil
      @connections = {}
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

    alias_method :publish_without_reset, :publish
    alias_method :publish, :publish_with_reset
  end

  class TestMessage < ActiveMessaging::BaseMessage

    def initialize(body="", headers={}, destination="")
      super(body, nil, headers, destination)
      @headers['destination'] = destination
    end

  end

  module TestHelper
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

  class MockLogger
    def error(*args) ; end
    def warn(*args) ; end
    def info(*args) ; end
    def debug(*args) ; end
  end
end
