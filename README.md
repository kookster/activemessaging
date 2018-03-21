# Active Messaging

ActiveMessaging is an attempt to bring the simplicity and elegance of rails development to the world of messaging. Messaging, (or event-driven architecture) is widely used for enterprise integration, with frameworks such as Java's JMS, and products such as ActiveMQ, Tibco, IBM MQSeries, etc.

ActiveMessaging is a generic framework to ease using messaging, but is not tied to any particular messaging system - in fact, it now has support for Stomp, AMQP, beanstalk, Amazon Simple Queue Service (SQS), JMS (using StompConnect or direct on JRuby), WebSphere MQ, a mock 'test' adapter, and a 'synch' adapter for use in development that processes calls synchronously (of course) and so requires no broker or additional processes to be running. 

Here's a sample of a processor class that handles incoming messages:

    class HelloWorldProcessor < ActiveMessaging::Processor
    	subscribes_to :hello_world
    	def on_message(message)
    		puts "received: " + message
    	end
    end

# Generating with Rails 3

After adding ActiveMessaging to your Gemfile and executing bundle install, run the following commands:

rails g active_messaging:install  
rails g active_messaging:processor <NameOfYourProcessor>

# Support

Best bet is the google groups mailing list:

http://groups.google.com/group/activemessaging-discuss
