require 'rubygems'
require 'net/http'
require 'openssl'
require 'base64'
require 'cgi'
require 'time'

module ActiveMessaging
  module Adapters
    module AmazonSQS

      class Connection
        include ActiveMessaging::Adapter

        register :asqs

        QUEUE_NAME_LENGTH = 1..80
        # MESSAGE_SIZE = 1..(256 * 1024)
        MESSAGE_SIZE = 1..(8 * 1024)
        VISIBILITY_TIMEOUT = 0..(24 * 60 * 60)
        NUMBER_OF_MESSAGES = 1..255
        GET_QUEUE_ATTRIBUTES = ['All', 'ApproximateNumberOfMessages', 'VisibilityTimeout']
        SET_QUEUE_ATTRIBUTES = ['VisibilityTimeout']

        #configurable params
        attr_accessor :reliable, :reconnectDelay, :access_key_id, :secret_access_key, :aws_version, :content_type, :host, :port, :poll_interval, :cache_queue_list
        
        #generic init method needed by a13g
        def initialize cfg
            raise "Must specify a access_key_id" if (cfg[:access_key_id].nil? || cfg[:access_key_id].empty?)
            raise "Must specify a secret_access_key" if (cfg[:secret_access_key].nil? || cfg[:secret_access_key].empty?)

            @access_key_id=cfg[:access_key_id]
            @secret_access_key=cfg[:secret_access_key]
            @request_expires = cfg[:requestExpires]         || 10
            @request_retry_count = cfg[:requestRetryCount]  || 5
            @aws_version = cfg[:aws_version]                || '2008-01-01'
            @content_type = cfg[:content_type]              || 'text/plain'
            @host = cfg[:host]                              || 'queue.amazonaws.com'
            @port = cfg[:port]                              || 80
            @protocol = cfg[:protocol]                      || 'http'
            @poll_interval = cfg[:poll_interval]            || 1
            @reconnect_delay = cfg[:reconnectDelay]         || 5
            @aws_url="#{@protocol}://#{@host}"

            @cache_queue_list = cfg[:cache_queue_list].nil? ? true : cfg[:cache_queue_list]
            @reliable =         cfg[:reliable].nil?         ? true : cfg[:reliable]
            
            #initialize the subscriptions and queues
            @subscriptions = {}
            @current_subscription = 0
            queues
        end

        def disconnect
          #it's an http request - there is no disconnect - ha!
        end

        # queue_name string, headers hash
        # for sqs, make sure queue exists, if not create, then add to list of polled queues
        def subscribe queue_name, message_headers={}
          # look at the existing queues, create any that are missing
          queue = get_or_create_queue queue_name
          if @subscriptions.has_key? queue.name
            @subscriptions[queue.name].add
          else
            @subscriptions[queue.name] = Subscription.new(queue.name, message_headers)
          end
        end

        # queue_name string, headers hash
        # for sqs, attempt delete the queues, won't work if not empty, that's ok
        def unsubscribe queue_name, message_headers={}
          if @subscriptions[queue_name]
            @subscriptions[queue_name].remove
            @subscriptions.delete(queue_name) if @subscriptions[queue_name].count <= 0
          end
        end

        # queue_name string, body string, headers hash
        # send a single message to a queue
        def send queue_name, message_body, message_headers={}
          queue = get_or_create_queue queue_name
          send_messsage queue, message_body
        end

        # receive a single message from any of the subscribed queues
        # check each queue once, then sleep for poll_interval
        def receive
          raise "No subscriptions to receive messages from." if (@subscriptions.nil? || @subscriptions.empty?)
          start = @current_subscription
          while true
            # puts "calling receive..."
            @current_subscription = ((@current_subscription < @subscriptions.length-1) ? @current_subscription + 1 : 0)
            sleep poll_interval if (@current_subscription == start)
            queue_name = @subscriptions.keys.sort[@current_subscription]
            queue = queues[queue_name]
            subscription = @subscriptions[queue_name]
            unless queue.nil?
              messages = retrieve_messsages queue, 1, subscription.headers[:visibility_timeout]
              return messages[0] unless (messages.nil? or messages.empty? or messages[0].nil?)
            end
          end
        end

        def received message, headers={}
          begin
            delete_message message
          rescue Object=>exception
            logger.error "Exception in ActiveMessaging::Adapters::AmazonSQS::Connection.received() logged and ignored: "
            logger.error exception
          end
        end

        def unreceive message, headers={}
          # do nothing; by not deleting the message will eventually become visible again
          return true
        end
        
        protected
        
        def create_queue(name)
          validate_new_queue name
      		response = make_request('CreateQueue', nil, {'QueueName'=>name})
          add_queue response.get_text("//QueueUrl") unless response.nil?
        end      	

        def delete_queue queue
          validate_queue queue
          response = make_request('DeleteQueue', "#{queue.queue_url}")
        end

        def list_queues(queue_name_prefix=nil)
          validate_queue_name queue_name_prefix unless queue_name_prefix.nil?
          params = queue_name_prefix.nil? ? {} : {"QueueNamePrefix"=>queue_name_prefix}
      		response = make_request('ListQueues', nil, params)
          response.nil? ? [] : response.nodes("//QueueUrl").collect{ |n| add_queue(n.text) }
        end
        
        def get_queue_attributes(queue, attribute='All')
          validate_get_queue_attribute(attribute)
          params = {'AttributeName'=>attribute}
          response = make_request('GetQueueAttributes', "#{queue.queue_url}")
          attributes = {}
          response.each_node('/GetQueueAttributesResponse/GetQueueAttributesResult/Attribute') { |n|
            n = n.elements['Name'].text
            v = n.elements['Value'].text
            attributes[n] = v
          }
          if attribute != 'All'
            attributes[attribute]
          else
            attributes
          end
        end

        def set_queue_attribute(queue, attribute, value)
          validate_set_queue_attribute(attribute)
          params = {'Attribute.Name'=>attribute, 'Attribute.Value'=>value.to_s}
          response = make_request('SetQueueAttributes', "#{queue.queue_url}", params)
        end

        def delete_queue queue
          validate_queue queue
          response = make_request('DeleteQueue', "#{queue.queue_url}")
        end

        # in progress
        def send_messsage queue, message
          validate_queue queue
          validate_message message
          response = make_request('SendMessage', queue.queue_url, {'MessageBody'=>message})
          response.get_text("//MessageId") unless response.nil?
        end

        def retrieve_messsages queue, num_messages=1, timeout=nil
          validate_queue queue
          validate_number_of_messages num_messages
          validate_timeout timeout if timeout

          params = {'MaxNumberOfMessages'=>num_messages.to_s}
          params['VisibilityTimeout'] = timeout.to_s if timeout

          response = make_request('ReceiveMessage', "#{queue.queue_url}", params)
          response.nodes("//Message").collect{ |n| Message.from_element n, response, queue } unless response.nil?
        end
        
        def delete_message message
          response = make_request('DeleteMessage', "#{message.queue.queue_url}", {'ReceiptHandle'=>message.receipt_handle})
        end

      	def make_request(action, url=nil, params = {})
          # puts "make_request a=#{action} u=#{url} p=#{params}"
      	  url ||= @aws_url
      	  
      		# Add Actions
      		params['Action'] = action
      		params['Version'] = @aws_version
      		params['AWSAccessKeyId'] = @access_key_id
      		params['Expires']= (Time.now + @request_expires).gmtime.iso8601
      		params['SignatureVersion'] = '1'

      		# Sign the string
      		sorted_params = params.sort_by { |key,value| key.downcase }
      		joined_params = sorted_params.collect { |key, value| key.to_s + value.to_s }
      		string_to_sign = joined_params.to_s
      		digest = OpenSSL::Digest::Digest.new('sha1')
          hmac = OpenSSL::HMAC.digest(digest, @secret_access_key, string_to_sign)
          params['Signature'] = Base64.encode64(hmac).chomp

          # Construct request
          query_params = params.collect { |key, value| key + "=" + CGI.escape(value.to_s) }.join("&")

          # Put these together to get the request query string
          request_url = "#{url}?#{query_params}"
          # puts "request_url = #{request_url}"
          request = Net::HTTP::Get.new(request_url)

          retry_count = 0
          while retry_count < @request_retry_count.to_i
      		  retry_count = retry_count + 1
            # puts "make_request try retry_count=#{retry_count}"
            begin
              response = SQSResponse.new(http_request(host,port,request))
              check_errors(response)
              return response
            rescue Object=>ex
              # puts "make_request caught #{ex}"
              raise ex unless reliable
        		  sleep(@reconnect_delay)
            end
          end
        end

        # I wrap this so I can move to a different client, or easily mock for testing
        def http_request h, p, r
          return Net::HTTP.start(h, p){ |http| http.request(r) }
        end

        def check_errors(response)
          raise "http response was nil" if (response.nil?)
          raise response.errors if (response && response.errors?)
          response
        end
        
        private
        
        # internal data structure methods
        def add_queue(url)
          q = Queue.from_url url
          queues[q.name] = q if self.cache_queue_list
          return q
        end

        def get_or_create_queue queue_name
          qs = queues
          qs.has_key?(queue_name) ? qs[queue_name] : create_queue(queue_name)
        end

        def queues
          return @queues if (@queues && cache_queue_list)
          @queues = {}
          list_queues.each{|q| @queues[q.name]=q }
          return @queues
        end

        # validation methods
        def validate_queue_name qn
          raise "Queue name, '#{qn}', must be between #{QUEUE_NAME_LENGTH.min} and #{QUEUE_NAME_LENGTH.max} characters." unless QUEUE_NAME_LENGTH.include?(qn.length)
          raise "Queue name, '#{qn}', must be alphanumeric only." if (qn =~ /[^\w\-\_]/ )
        end

        def validate_new_queue qn
          validate_queue_name qn
          raise "Queue already exists: #{qn}" if queues.has_key? qn
        end

        def validate_queue q
            raise "Never heard of queue, can't use it: #{q.name}" unless queues.has_key? q.name
        end

        def validate_message m
          raise "Message cannot be nil." if m.nil?
          raise "Message length, #{m.length}, must be between #{MESSAGE_SIZE.min} and #{MESSAGE_SIZE.max}." unless MESSAGE_SIZE.include?(m.length)
        end

        def validate_timeout to
          raise "Timeout, #{to}, must be between #{VISIBILITY_TIMEOUT.min} and #{VISIBILITY_TIMEOUT.max}." unless VISIBILITY_TIMEOUT.include?(to)
        end

        def validate_get_queue_attribute qa
          raise "Queue Attribute name, #{qa}, not in list of valid attributes to get: #{GET_QUEUE_ATTRIBUTES.to_sentence}." unless GET_QUEUE_ATTRIBUTES.include?(qa)
        end

        def validate_set_queue_attribute qa
          raise "Queue Attribute name, #{qa}, not in list of valid attributes to set: #{SET_QUEUE_ATTRIBUTES.to_sentence}." unless SET_QUEUE_ATTRIBUTES.include?(qa)
        end

        def validate_number_of_messages nom
          raise "Number of messages, #{nom}, must be between #{NUMBER_OF_MESSAGES.min} and #{NUMBER_OF_MESSAGES.max}." unless NUMBER_OF_MESSAGES.include?(nom)
        end

      end

      class SQSResponse
        attr_accessor :headers, :doc, :http_response
        
        def initialize response
          # puts "response.body = #{response.body}"
          @http_response = response
          @headers = response.to_hash()
          @doc = REXML::Document.new(response.body)
        end
      
        def message_type
          return doc ? doc.root.name : ''
        end

        def errors?
          (not http_response.kind_of?(Net::HTTPSuccess)) or (message_type == "ErrorResponse")
        end

        def errors
          return "HTTP Error: #{http_response.code} : #{http_response.message}" unless http_response.kind_of?(Net::HTTPSuccess)

          msg = nil
          each_node('//Error') { |n|
            msg ||= ""
            c = n.elements['Code'].text
            m = n.elements['Message'].text
            msg << ", " if msg != ""
            msg << "#{c} : #{m}"
          }

          return msg
        end
      
        def get_text(xpath,default='')
          e = REXML::XPath.first( doc, xpath)
          e.nil? ? default : e.text
        end
      
        def each_node(xp)
          REXML::XPath.each(doc.root, xp) {|n| yield n}
        end
      
        def nodes(xp)
          doc.elements.to_a(xp)
        end
      end

      class Subscription
        attr_accessor :name, :headers, :count
        
        def initialize(destination, headers={}, count=1)
          @destination, @headers, @count = destination, headers, count
        end
        
        def add
          @count += 1
        end

        def remove
          @count -= 1
        end

      end

      class Queue
        attr_accessor :name, :pathinfo, :domain, :visibility_timeout

        def self.from_url url
          return Queue.new($2,$1) if (url =~ /^http:\/\/(.+)\/([-a-zA-Z0-9_]+)$/)
          raise "Bad Queue URL: #{url}"
        end

        def queue_url
          "#{pathinfo}/#{name}"
        end

        def initialize name, domain, vt=nil
          @name, @pathinfo, @domain, @visibility_timeout = name, pathinfo, domain, vt
        end

        def to_s
          "<AmazonSQS::Queue name='#{name}' url='#{queue_url}' domain='#{domain}'>"
        end
      end

      # based on stomp message, has pointer to the SQSResponseObject
      class Message
        attr_accessor :headers, :id, :body, :command, :response, :queue, :md5_of_body, :receipt_handle
        
        def self.from_element e, response, queue
          Message.new(response.headers, e.elements['MessageId'].text, e.elements['Body'].text, e.elements['MD5OfBody'].text, e.elements['ReceiptHandle'].text, response, queue)
        end
      
        def initialize headers, id, body, md5_of_body, receipt_handle, response, queue, command='MESSAGE'
          @headers, @id, @body, @md5_of_body, @receipt_handle, @response, @queue, @command =  headers, id, body, md5_of_body, receipt_handle, response, queue, command
          headers['destination'] = queue.name
        end

      
        def to_s
          "<AmazonSQS::Message id='#{id}' body='#{body}' headers='#{headers.inspect}' command='#{command}' response='#{response}'>"
        end
      end
   
    end
  end
end