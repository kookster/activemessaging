#!/usr/bin/env ruby
#make sure stdout and stderr write out without delay for using with daemon like scripts
STDOUT.sync = true; STDOUT.flush
STDERR.sync = true; STDERR.flush

#Load the environment and the plugin init
RAILS_ROOT=File.expand_path(File.join(File.dirname(__FILE__), '..','..','..'))
load File.join(RAILS_ROOT, 'config', 'environment.rb')
load File.join(RAILS_ROOT, 'config', 'messaging.rb')

#Load the parent processor.rb, then all child processor classes
puts "Loading #{RAILS_ROOT + '/app/processors/application.rb'}"; load RAILS_ROOT + '/app/processors/application.rb'
Dir[RAILS_ROOT + '/app/processors/*_processor.rb'].each{|f| puts "Loading #{f}"; load f}

#See if there are any subscriptions
if ActiveMessaging::Gateway.subscriptions.empty?
  puts "No subscriptions."
  puts "If you have no processor classes in app/processors, add them using the command:"
  puts "  script/generate processor DoSomething"
  puts "If you have processor classes, make sure they include in the class a call to 'subscribes_to':"
  puts "  class DoSomethingProcessor < ActiveMessaging::Processor"
  puts "    subscribes_to :do_something"
  exit
end

ActiveMessaging::Gateway.subscribe
puts "=> All subscribed, now polling"

begin
  while true
      ActiveMessaging::Gateway.dispatch_next
  end
rescue Interrupt
  puts "\n<<Interrupt received>>\n"  
rescue
  puts "#{$!.class.name}:\n #{$!.message}\n\t#{$!.backtrace.join('\n\t')}"
  raise $!
ensure
  puts "Cleaning up..."
  ActiveMessaging::Gateway.disconnect
  puts "=> Disconnected from messaging server"
  puts "=> END"
end
