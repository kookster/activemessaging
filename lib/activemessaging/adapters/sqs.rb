require 'rubygems'
require 'net/http'
require 'net/https'
require 'openssl'
require 'base64'
require 'cgi'
require 'time'
require 'uri'
require 'rexml/document'

require 'activemessaging/adapters/base'
require 'activemessaging/adapters/aws4_signer'

module ActiveMessaging
  module Adapters
    module Sqs

      class Connection < ActiveMessaging::Adapters::BaseConnection
        register :sqs

        QUEUE_NAME_LENGTH    = 1..80
        VISIBILITY_TIMEOUT   = 0..(24 * 60 * 60)
        NUMBER_OF_MESSAGES   = 1..255
        GET_QUEUE_ATTRIBUTES = ['All', 'ApproximateNumberOfMessages', 'ApproximateNumberOfMessagesDelayed', 'ApproximateNumberOfMessagesNotVisible', 'CreatedTimestamp', 'DelaySeconds', 'LastModifiedTimestamp', 'MaximumMessageSize', 'MessageRetentionPeriod', 'Policy', 'QueueArn', 'ReceiveMessageWaitTimeSeconds', 'RedrivePolicy', 'VisibilityTimeout', 'KmsMasterKeyId', 'KmsDataKeyReusePeriodSeconds', 'FifoQueue', 'ContentBasedDeduplication'].freeze
        SET_QUEUE_ATTRIBUTES = ['DelaySeconds', 'MaximumMessageSize', 'MessageRetentionPeriod', 'Policy', 'ReceiveMessageWaitTimeSeconds', 'RedrivePolicy', 'VisibilityTimeout', 'KmsMasterKeyId', 'KmsDataKeyReusePeriodSeconds', 'ContentBasedDeduplication'].freeze
        URI_ENCODING_REPLACEMENTS = { '%7E' => '~', '+' => '%20' }.freeze

        #configurable params
        attr_accessor :reconnect_delay, :access_key_id, :secret_access_key, :aws_version, :content_type, :host, :port, :poll_interval, :cache_queue_list, :max_message_size

        #generic init method needed by a13g
        def initialize cfg
          raise "Must specify a access_key_id" if (cfg[:access_key_id].nil? || cfg[:access_key_id].empty?)
          raise "Must specify a secret_access_key" if (cfg[:secret_access_key].nil? || cfg[:secret_access_key].empty?)

          @access_key_id = cfg[:access_key_id]
          @secret_access_key = cfg[:secret_access_key]
          @region = cfg[:region]                          || 'us-east-1'
          @request_expires = cfg[:requestExpires]         || 10
          @request_retry_count = cfg[:requestRetryCount]  || 5
          @aws_version = cfg[:aws_version]                || '2012-11-05'
          @content_type = cfg[:content_type]              || 'text/plain'
          @host = cfg[:host]                              || "sqs.#{@region}.amazonaws.com"
          @port = cfg[:port]                              || 80
          @protocol = cfg[:protocol]                      || 'http'
          @poll_interval = cfg[:poll_interval]            || 1
          @reconnect_delay = cfg[:reconnectDelay]         || 5

          @max_message_size = cfg[:max_message_size].to_i > 0 ? cfg[:max_message_size].to_i : 8

          @aws_url = "#{@protocol}://#{@host}/"

          @cache_queue_list = cfg[:cache_queue_list].nil? ? true : cfg[:cache_queue_list]
          @reliable =         cfg[:reliable].nil?         ? true : cfg[:reliable]

          #initialize the subscriptions and queues
          @subscriptions = {}
          @queues_by_priority = {}
          @current_subscription = 0
          queues
        end

        def disconnect
          return true
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
          priority = @subscriptions[queue.name].priority

          @queues_by_priority[priority] = [] unless @queues_by_priority.has_key?(priority)
          @queues_by_priority[priority] << queue.name unless @queues_by_priority[priority].include?(queue.name)
        end

        # queue_name string, headers hash
        # for sqs, attempt delete the queues, won't work if not empty, that's ok
        def unsubscribe queue_name, message_headers={}
          if @subscriptions[queue_name]
            @subscriptions[queue_name].remove
            if @subscriptions[queue_name].count <= 0
              sub = @subscriptions.delete(queue_name)
              @queues_by_priority[sub.priority].delete(queue_name)
            end
          end
        end

        # queue_name string, body string, headers hash
        # send a single message to a queue
        def send(queue_name, message_body, message_headers = {})
          queue = get_or_create_queue(queue_name)
          send_messsage queue, message_body
        end

        #  new receive respects priorities
        def receive(options = {})
          message = nil

          only_priorities = options[:priorities]

          # loop through the priorities
          @queues_by_priority.keys.sort.each do |priority|

            # skip this priority if there is a list, and it is not in the list
            next if only_priorities && !only_priorities.include?(priority.to_i)

            # loop through queues for the same priority in random order each time
            @queues_by_priority[priority].shuffle.each do |queue_name|
              queue = queues[queue_name]
              subscription = @subscriptions[queue_name]

              next if queue.nil? || subscription.nil?
              messages = retrieve_messsages(queue, 1, subscription.headers[:visibility_timeout])

              if (messages && !messages.empty?)
                message = messages[0]
              end

              break if message
            end

            break if message
          end
          message
        end

        def received(message, headers={})
          begin
            delete_message(message)
          rescue Object => exception
            logger.error "Exception in ActiveMessaging::Adapters::AmazonSWS::Connection.received() logged and ignored: "
            logger.error exception
          end
        end

        # do nothing; by not deleting the message will eventually become visible again
        def unreceive(message, headers = {})
          return true
        end

        def create_queue(name)
          validate_new_queue name
      		response = make_request('CreateQueue', nil, { 'QueueName' => name }, {
            'DelaySeconds' => 0,
            'MaximumMessageSize' => 262144,
            'MessageRetentionPeriod' => 4 * 24 * 60 * 60,
            'ReceiveMessageWaitTimeSeconds' => 0,
            'VisibilityTimeout' => 90 * 60
          })
          add_queue(response.get_text("/CreateQueueResponse/CreateQueueResult/QueueUrl")) unless response.nil?
        end

        def delete_queue(queue)
          validate_queue queue
          response = make_request('DeleteQueue', queue.queue_url)
          queues.delete(queue.name)
        end

        def list_queues(queue_name_prefix = nil)
          validate_queue_name queue_name_prefix unless queue_name_prefix.nil?
          params = queue_name_prefix.nil? ? {} : { "QueueNamePrefix" => queue_name_prefix }
      		response = make_request('ListQueues', nil, params)
          response.nil? ? [] : response.nodes("/ListQueuesResponse/ListQueuesResult/QueueUrl").collect{ |n| add_queue(n.text) }
        end

        def get_queue_attributes(queue, attributes = ['All'])
          params = {}
          attributes.each_with_index do |attribute, i|
            validate_get_queue_attribute(attribute)
            params["AttributeName.#{i+1}"] = attribute
          end
          response = make_request('GetQueueAttributes', queue.queue_url, params)
          attributes = {}
          response.each_node('/GetQueueAttributesResponse/GetQueueAttributesResult/Attribute') { |n|
            name = n.elements['Name'].text
            value = n.elements['Value'].text
            attributes[name] = value
          }
          attributes
        end

        def set_queue_attributes(queue, attributes)
          attributes.keys.each { |a| validate_set_queue_attribute(a) }
          response = make_request('SetQueueAttributes', queue.queue_url, {}, attributes)
        end

        def delete_queue(queue)
          validate_queue queue
          response = make_request('DeleteQueue', queue.queue_url)
        end

        def send_messsage(queue, message)
          validate_queue queue
          validate_message message
          response = make_request('SendMessage', queue.queue_url, { 'MessageBody' => message })
          response.get_text('/SendMessageResponse/SendMessageResult/MessageId') unless response.nil?
        end

        def retrieve_messsages(queue, num_messages = 1, timeout = nil, waittime = nil)
          validate_queue queue
          validate_number_of_messages num_messages
          validate_timeout timeout if timeout

          params = { 'MaxNumberOfMessages' => num_messages.to_s, 'AttributeName' => 'All' }
          params['VisibilityTimeout'] = timeout.to_s if timeout
          params['WaitTimeSeconds'] = waittime.to_s if waittime

          response = make_request('ReceiveMessage', queue.queue_url, params)
          response.nodes('/ReceiveMessageResponse/ReceiveMessageResult/Message').map do |n|
            Message.from_element(n, response, queue)
          end unless response.nil?
        end

        def delete_message message
          response = make_request('DeleteMessage', message.queue.queue_url, { 'ReceiptHandle' => message.receipt_handle })
        end

      	def make_request(action, url=nil, params = {}, attributes = {})
      	  url ||= @aws_url

      		params['Action'] = action
      		params['Version'] = @aws_version
          params['Expires']= (Time.now + @request_expires).utc.iso8601

          attributes.keys.sort.each_with_index do |k, i|
            params["Attributes.#{i + 1}.Name"] = k
            params["Attributes.#{i + 1}.Value"] = attributes[k]
          end

          # Sort and encode query params
          query_params = params.keys.sort.map do |key|
            key + "=" + url_encode(params[key])
          end

          # Put these together with the uri to get the request query string
          request_url = "#{url}?#{query_params.join("&")}"

          # Create the request
          init_headers = {
            'Date' => Time.now.utc.iso8601,
            'Host' => @host
          }
          request = Net::HTTP::Get.new(request_url, init_headers)

          # Sign the request
          signer = AWS4Signer.new({
            :access_key => @access_key_id,
            :secret_key => @secret_access_key,
            :region => @region
          })

          headers = {}
          request.canonical_each { |k, v| headers[k] = v }

          signature = signer.sign('GET', URI.parse(request_url), headers, nil, false)
          signature.each { |k, v| request[k] = v }

          # Make the request
          retry_count = 0
          while retry_count < @request_retry_count.to_i
      		  retry_count = retry_count + 1
            begin
              http_response = http_request(host,port,request)
              response = SQSResponse.new(http_response)
              check_errors(response)
              return response
            rescue Object=>ex
              raise ex unless reliable
        		  sleep(@reconnect_delay)
            end
          end
        end

        def url_encode(param)
          param = param.to_s

          if param.respond_to?(:encode)
            param = param.encode('UTF-8')
          end

          param = CGI::escape(param)
          URI_ENCODING_REPLACEMENTS.each { |k, v| param = param.gsub(k, v) }
          param
        end

        def http_request h, p, r
          http = Net::HTTP.new(h, p)
          # http.set_debug_output(STDOUT)

          http.use_ssl = 'https' == @protocol

          # Don't carp about SSL cert verification
          http.verify_mode = OpenSSL::SSL::VERIFY_NONE
          return http.request(r)
        end

        def check_errors(response)
          raise 'http response was nil' if (response.nil?)
          raise response.errors if (response && response.errors?)
          response
        end

        def queues
          return @queues if (@queues && cache_queue_list)
          @queues = {}
          list_queues.each { |q| @queues[q.name] = q }
          return @queues
        end

        # internal data structure methods

        def add_queue(url)
          q = Queue.from_url url
          queues[q.name] = q if self.cache_queue_list
          return q
        end

        def get_or_create_queue queue_name
          qs = queues
          q = qs.has_key?(queue_name) ? qs[queue_name] : create_queue(queue_name)
          raise "could not get or create queue: #{queue_name}" unless q
          q
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
          raise "Message length, #{m.length}, must be between #{message_size_range.min} and #{message_size_range.max}." unless message_size_range.include?(m.length)
        end

        def message_size_range
          @_message_size_range ||= 1..(max_message_size * 1024)
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
          (not http_response.kind_of?(Net::HTTPSuccess)) or (message_type == 'ErrorResponse')
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
        attr_accessor :destination, :headers, :count, :priority

        def initialize(destination, headers={}, count=1)
          @priority = headers.delete(:priority) || 1001
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
        attr_accessor :url, :name, :pathinfo, :domain, :visibility_timeout

        def self.from_url url
          uri = URI.parse(url)
          name = uri.path.split('/').last
          domain = uri.host
          return Queue.new(name, uri)
        end

        def queue_url
          url.to_s
        end

        def initialize name, url, vt=nil
          @name, @url, @visibility_timeout = name, url, vt
        end

        def to_s
          "<AmazonSQS::Queue name='#{name}' url='#{url}' visibility_timeout='#{visibility_timeout}'>"
        end
      end

      # based on stomp message, has pointer to the SQSResponseObject
      class Message < ActiveMessaging::BaseMessage
        attr_accessor :response, :queue, :md5_of_body, :receipt_handle, :request_id, :attributes

        def self.from_element(e, response, queue)
          attributes = {}
          e.elements.each('Attribute') { |n| attributes[n.elements['Name'].text] = n.elements['Value'].text }

          Message.new(
            e.elements['Body'].text,
            response.headers,
            e.elements['MessageId'].text,
            e.elements['MD5OfBody'].text,
            e.elements['ReceiptHandle'].text,
            attributes,
            response,
            queue)
        end

        def initialize body, headers, id, md5_of_body, receipt_handle, attributes, response, queue
          super(body, id, headers, queue.name)
          @md5_of_body, @receipt_handle, @response, @queue =  md5_of_body, receipt_handle, response, queue
        end

        def to_s
          "<AmazonSQS::Message id='#{id}' body='#{body}' headers='#{headers.inspect}' attributes='#{attributes.inspect}' response='#{response}'>"
        end
      end

    end
  end
end
