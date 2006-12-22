require 'ostruct'

require 'activemessaging/gateway'
require 'activemessaging/processor'
require 'activemessaging/trace_filter'
require 'activemessaging/adapters/stomp'

begin
  load 'config/messaging.rb'
rescue MissingSourceFile
end