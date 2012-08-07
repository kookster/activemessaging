module ActiveMessaging

  class BaseMessage
    attr_accessor :body, :id, :headers, :destination

    def initialize(body=nil, id=nil, headers={}, destination=nil)
      @body, @id, @headers, @destination = body, id, headers, destination
    end

    def matches_subscription?(subscription)
      self.destination.to_s == subscription.destination.value.to_s
    end

    def dup
      super.tap do |copy|
        [:body, :id, :headers, :destination].each do |field_name|
          value = send field_name
          copy.send "#{field_name}=", (value.duplicable? ? value.dup : value)
        end
      end
    end

    def to_s      
      "<#{self.class.name} id='#{id}' headers='#{headers.inspect}' body='#{body}' >"
    end
  end

end
