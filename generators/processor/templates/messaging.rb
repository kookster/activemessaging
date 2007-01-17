#
# Add your queue definitions here
#
ActiveMessaging::Gateway.define do |s|
  #s.queue :orders, '/queue/Orders'
  #s.connection_configuration = {:reliable => true}
  #s.filter MyFilter.new
  
  s.queue :<%= singular_name %>, '/queue/<%= class_name %>'
  
end