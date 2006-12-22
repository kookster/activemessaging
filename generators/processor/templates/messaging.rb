#
# Add your queue definitions here
#
ActiveMessaging::Gateway.define do |s|
  #s.queue :orders, '/queue/Orders'

  #s.filter MyFilter.new
end