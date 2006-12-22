class TraceFilter
  include ActiveMessaging::MessageSender
  
  def initialize(queue)
    @queue = queue
    TraceFilter.publishes_to @queue
  end
  
  def process message, routing
    
    puts "Trace: direction = #{routing[:direction]} publisher=#{routing[:publisher]} queue=#{routing[:queue]} @queue=#{@queue}"
    
    unless ( routing[:queue]==ActiveMessaging::Gateway.find_queue(@queue) ) then
      if routing[:direction]==:outgoing then
        publish @queue, "<sent>"+
                        "<from>#{routing[:publisher]}</from>" +        
                        "<queue>#{routing[:queue]}</queue>" +
                        "<message>#{message.body}</message>" + 
                        "</sent>"
      end
      if routing[:direction]==:incoming then
        publish @queue, "<received>"+
                        "<by>#{routing[:receiver]}</by>" +        
                        "<queue>#{routing[:queue]}</queue>" +
                        "<message>#{message.body}</message>" + 
                        "</received>"
      end
    end
    yield
  end
  
end

