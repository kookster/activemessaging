#
# contributed by Al-Faisal El-Dajani on 11/04/2009
#
# One caveat: beanstalk does not accept the underscore '_' as a legal character in queue names. 
# So in messaging.rb you'll need to modify your queue names to use something other than the underscore, a dash perhaps.
# Accepting the underscore as a valid char in queue names is an open issue in beanstalk, and should be fixed in a future version.
#

require 'beanstalk-client'
require 'activemessaging/adapters/base'

module ActiveMessaging
  module Adapters
    module Beanstalk
      
      class Connection < ActiveMessaging::Adapters::BaseConnection
        register :beanstalk
        
        attr_accessor :connection, :host, :port
        
        def initialize cfg
          @host = cfg[:host] || 'localhost'
          @port = cfg[:port] || 11300
          
          @connection = ::Beanstalk::Pool.new("#{@host}:#{@port}")
        end
        
        def disconnect
          @connection.close
        end
        
        def subscribe tube, message_headers={}
          @connection.watch(tube)
        end
        
        def unsubscribe tube, message_headers={}
          @connection.ignore(tube)
        end
        
        def send tube, message, message_headers={}
          priority = message_headers[:priority] || 65536
          delay    = message_headers[:delay] || 0
          ttr      = message_headers[:ttr] || 120
          
          @connection.use(tube)
          @connection.put(message, priority, delay, ttr)
        end
        
        def receive
          message = @connection.reserve
          Beanstalk::Message.new message
        end
        
        def received message, message_headers={}
          message.delete
        end
        
        def unreceive message, message_headers={}
          message.release
        end
        
      end
      
      class Message < ActiveMessaging::BaseMessage
        attr_accessor :beanstalk_job
        
        def initialize beanstalk_job
          bsh = {
            'destination' => beanstalk_job.stats['tube'],
            'priority'    => beanstalk_job.pri,
            'delay'       => beanstalk_job.delay,
            'ttr'         => beanstalk_job.ttr
          }
          super(beanstalk_job.body, beanstalk_job.id, bsh, beanstalk_job.stats['tube'])
          @beanstalk_job = beanstalk_job
        end
        
        def delete
          @beanstalk_job.delete
        end
        
        def release
          @beanstalk_job.release
        end
      end
    end
  end
end
