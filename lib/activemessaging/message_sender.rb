require 'logger'

module ActiveMessaging

  # This is a module so that we can send messages from (for example) web page controllers, or can receive a single message
  module MessageSender

    def self.included(included_by)
      class << included_by
        def publishes_to destination_name
          Gateway.find_destination destination_name
        end

        def receives_from destination_name
          Gateway.find_destination destination_name
        end
      end
    end

    def publish destination_name, message, headers={}, timeout=10
      Gateway.publish(destination_name, message, self.class, headers, timeout)
    end

    def receive destination_name, headers={}, timeout=10
      Gateway.receive(destination_name, self.class, headers, timeout)
    end

  end

end