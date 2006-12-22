RAILS_ROOT=File.dirname(__FILE__) + '/../../../'
load RAILS_ROOT + '/config/environment.rb'

Dir[RAILS_ROOT + '/app/processors/*.rb'].each{|f| puts "Loading #{f}"; load f}

if ActiveMessaging::Gateway.subscriptions.empty?
  puts "No subscriptions."
  puts "Create a file named 'config/subscriptions.rb'."
  puts "Start with an example by executing:"
  puts "  cp vendor/plugins/activemessaging/subscriptions.rb.example config/subscriptions.rb (on Mac/Unix)"
  puts "  copy vendor/plugins/activemessaging/subscriptions.rb.example config/subscriptions.rb (on Windows)"
  puts "(Yes, I'll handle this better later on.)"
  exit
end

ActiveMessaging::Gateway.subscribe
puts "=> All subscribed, now polling"

while true
  ActiveMessaging::Gateway.dispatch_next
end
