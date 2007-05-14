class TraceFilter
  include ActiveMessaging::MessageSender
  
  def initialize(queue)
    @queue = queue
    TraceFilter.publishes_to @queue
  end
  
  def process message, routing
    
    unless ( routing[:queue].name == @queue ) then
      puts "Trace: direction = #{routing[:direction]} publisher=#{routing[:publisher]} queue=#{routing[:queue].name} @queue=#{@queue}"
      if routing[:direction].to_sym==:outgoing then
        "trace from outgoing"
        publish @queue, "<sent>"+
                        "<from>#{routing[:publisher]}</from>" +        
                        "<queue>#{routing[:queue].name}</queue>" +
                        "<message>#{message.body}</message>" + 
                        "</sent>"
      end
      if routing[:direction].to_sym==:incoming then
        "trace from incoming"
        publish @queue, "<received>"+
                        "<by>#{routing[:receiver]}</by>" +        
                        "<queue>#{routing[:queue].name}</queue>" +
                        "<message>#{message.body}</message>" + 
                        "</received>"
      end
    end
    yield
  end
  
end

