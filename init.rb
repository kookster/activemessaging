require 'ostruct'

require 'activemessaging/gateway'
require 'activemessaging/processor'
require 'activemessaging/trace_filter'
require 'activemessaging/adapter'

# load all under the adapters dir 
Dir[RAILS_ROOT + '/vendor/plugins/activemessaging/lib/activemessaging/adapters/*.rb'].each{|a| 
  require 'activemessaging/adapters/' + File.basename(a, ".rb")
}

begin
  load 'config/messaging.rb'
rescue MissingSourceFile
end