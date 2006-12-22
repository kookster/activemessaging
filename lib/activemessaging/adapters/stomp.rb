require_gem 'stomp'
require 'stomp'

module ActiveMessaging
  module Adapters
    module Stomp
      
      class Connection < ::Stomp::Connection
        def initialize(configuration)
          configuration[:login] ||= ""
          configuration[:passcode] ||= ""
          configuration[:host] ||= "localhost"
          configuration[:port] ||= "61613"
          super(configuration[:login], configuration[:passcode], configuration[:host], configuration[:port].to_i)
        end
      end
      
    end
  end
end