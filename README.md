ActiveMessaging is an attempt to bring the simplicity and elegance of rails development to the world of messaging. Messaging, (or event-driven architecture) is widely used for enterprise integration, with frameworks such as Java's JMS, and products such as ActiveMQ, Tibco, IBM MQSeries, etc.

ActiveMessaging is a generic framework to ease using messaging, but is not tied to any particular messaging system - in fact, it now has support for Stomp, Amazon Simple Queue Service (SQS), Beanstalk, JMS (using StompConnect or [JMSWithJRuby direct on JRuby]), WebSphere MQ, and the all-Ruby ReliableMessaging.

Here's a sample of a processor class that handles incoming messages:

    class HelloWorldProcessor < ActiveMessaging::Processor
    	subscribes_to :hello_world
        
        def on_message(message)
        	puts "received: " + message
      	end
    end


Support

Best bet is the google groups mailing list:

http://groups.google.com/group/activemessaging-discuss
