#
# Add your queue definitions here
#
ActiveMessaging::Gateway.define do |s|
  #s.connection_configuration = {:reliable => true}
  #s.queue :orders, '/queue/Orders'
  #s.processor_group :group1, :order_processor
  
  s.queue :<%= singular_name %>, '/queue/<%= class_name %>'
  
end