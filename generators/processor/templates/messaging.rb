#
# Add your destination definitions here
# can also be used to configure filters, and processor groups
#
ActiveMessaging::Gateway.define do |s|
  #s.destination :orders, '/queue/Orders'
  #s.filter :incoming, MyFilter.new
  #s.processor_group :group1, :order_processor
  
  s.destination :<%= singular_name %>, '/queue/<%= class_name %>'
  
end