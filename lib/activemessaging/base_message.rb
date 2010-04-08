module ActiveMessaging

  class BaseMessage
    attr_accessor :body, :id, :headers, :destination

    def initialize(body=nil, id=nil, headers={}, destination=nil)
      @body, @id, @headers, @destination = body, id, headers, destination
    end
    
    def matches_subscription?(subscription)
      self.destination.to_s == subscription.destination.value.to_s
    end

    def to_s      
      "<#{self.class.name} id='#{id}' headers='#{headers.inspect}' body='#{body}' >"
    end
  end

end