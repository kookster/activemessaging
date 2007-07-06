module ActiveMessaging
  module Adapters
    module AmazonSQS

      class Connection
        include ActiveMessaging::Adapter

        register :asqs

        QUEUE_NAME = 1..80
        MESSAGE_SIZE = 1..(256 * 1024)
        VISIBILITY_TIMEOUT = 0..(24 * 60 * 60)
        NUMBER_OF_MESSAGES = 1..255

        #configurable params
        attr_accessor :reliable, :reconnectDelay, :access_key_id, :secret_access_key, :aws_version, :content_type, :host, :port, :poll_interval, :cache_queue_list
        
        #generic init method needed by a13g
        def initialize cfg
            raise "Must specify a access_key_id" if (cfg[:access_key_id].nil? || cfg[:access_key_id].empty?)
            raise "Must specify a secret_access_key" if (cfg[:secret_access_key].nil? || cfg[:secret_access_key].empty?)

            @access_key_id=cfg[:access_key_id]
            @secret_access_key=cfg[:secret_access_key]
            @aws_version = cfg[:aws_version]            || '2006-04-01' 
            @content_type = cfg[:content_type]          || 'text/plain'
            @host = cfg[:host]                          || 'queue.amazonaws.com'
            @port = cfg[:port]                          || 80
            @poll_interval = cfg[:poll_interval]        || 1
            @cache_queue_list = cfg[:cache_queue_list]  || true
            @reliable = cfg[:reliable]                  || true
            @reconnectDelay = cfg[:reconnectDelay]      || 5
            
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
            @subscriptions[queue.name] += 1
          else
            @subscriptions[queue.name] = 1 
          end
        end

        # queue_name string, headers hash
        # for sqs, attempt delete the queues, won't work if not empty, that's ok
        def unsubscribe queue_name, message_headers={}
          @subscriptions[queue_name] -= 1
          @subscriptions.delete(queue_name) if @subscriptions[queue_name] <= 0
        end

        # queue_name string, body string, headers hash
        # send a single message to a queue
        def send queue_name, message_body, message_headers
          queue = get_or_create_queue queue_name
          send_messsage queue, message_body
        end

        # receive a single message from any of the subscribed queues
        # check each queue once, then sleep for poll_interval
        def receive
          raise "No subscriptions to receive messages from." if (@subscriptions.nil? || @subscriptions.empty?)
          start = @current_subscription
          while true
            @current_subscription = ((@current_subscription < @subscriptions.length-1) ? @current_subscription + 1 : 0)
            sleep poll_interval if (@current_subscription == start)
            queue_name = @subscriptions.keys.sort[@current_subscription]
            queue = queues[queue_name]
            unless queue.nil?
              messages = retrieve_messsages queue, 1
              return messages[0] unless (messages.nil? or messages.empty? or messages[0].nil?)
            end
          end
        end

        def received message, headers={}
          delete_message message
        end
        
        protected
        
        #belows are the methods from the REST API
        def create_queue queue_name
          validate_new_queue queue_name
          response = transmit 'POST', "/?QueueName=#{queue_name}"
          add_queue response.get_text("//QueueUrl") unless response.nil?
        end

        def list_queues queue_name_prefix=nil
          validate_queue_name queue_name_prefix unless queue_name_prefix.nil?
          response = transmit 'GET', queue_name_prefix.nil? ? '/' : "/?QueueNamePrefix=#{queue_name_prefix}"
          response.nil? ? [] : response.nodes("//QueueUrl").collect{ |n| add_queue(n.text) }
        end
        
        def delete_queue queue
          validate_queue queue
          response = transmit 'DELETE', "#{queue.queue_url}", queue.domain
        end
        
        def send_messsage queue, message
          validate_queue queue
          validate_message message
          response = transmit 'PUT', "#{queue.queue_url}/back", queue.domain, message
        end
        
        def set_visibility_timeout queue, timeout
          validate_queue queue
          validate_timeout timeout
          response = transmit 'PUT', "#{queue.queue_url}?VisibilityTimeout=#{timeout}", queue.domain
        end

        def retrieve_messsages queue, num_messages=1, timeout=nil
          validate_queue queue
          validate_number_of_messages num_messages
          validate_timeout timeout if timeout
          timeout_path = timeout ? "VisibilityTimeout=#{timeout}&" : ''
          response = transmit 'GET', "#{queue.queue_url}/front?#{timeout_path}NumberOfMessages=#{num_messages}", queue.domain
          response.nodes("//Message").collect{ |n| Message.from_element n, response, queue } unless response.nil?
        end
        
        def get_visibility_timeout queue
          validate_queue queue
          response = transmit 'GET', "#{queue.queue_url}/", queue.domain
          response.get_text('//VisibilityTimeout').to_i
        end
        
        def delete_message message
          delete_message_by_id message.queue, message.id
        end

        def delete_message_by_id queue, message_id
          response = transmit 'DELETE', "#{queue.queue_url}/#{message_id}", queue.domain
        end

        def peek_message queue, message_id
          response = transmit 'GET', "#{queue.queue_url}/#{message_id}", queue.domain
          Message.from_element( response.node('//Message'), response, queue)
        end
        
        private
        
        def queues
          return @queues if (@queues && cache_queue_list)
          @queues = {}
          list_queues.each{|q| @queues[q.name]=q }
          return @queues
        end

        def get_or_create_queue queue_name
          qs = queues
          qs.has_key?(queue_name) ? qs[queue_name] : create_queue(queue_name)
        end
        
        def add_queue(url)
          q = Queue.from_url url
          queues[q.name] = q if cache_queue_list
          return q
        end

        # method to do the actual send, generic to get, post, delete, etc.
        # action - possible values: get, post, delete
        def transmit(command, url, h=host, body=nil, headers={}, p=port)
          request_headers = create_headers(command, url, headers, body)
          request = http_request_factory(command, url, request_headers, body)
          tryit = true
          while tryit
            begin
              response = SQSResponse.new(Net::HTTP.start(h, p){ |http| http.request(request) })
              tryit = false unless response.nil?
            rescue
              raise $! unless reliable
              puts "transmit failed, will retry in #{@reconnectDelay} seconds"
              sleep @reconnectDelay
            end
          end
          # p response
          # puts "body: #{response.http_response.body}"
          check_errors(response)
        end
        
        def create_headers(cmd, url, headers, body)
          # set then merge the headers
          hdrs = { 'AWS-Version'=>@aws_version, 
                   'Date'=>Time.now.httpdate, 
                   'Content-type'=>@content_type }
          hdrs['Content-Length'] = body.length.to_s if (body && (cmd=='POST' or cmd=='PUT'))
          

          #merge with the passed in headers to allow overrides
          hdrs.merge! headers
          
          # calculate authorization based on set headers
          hdrs['Authorization'] = create_authorization_signature(cmd, url, hdrs)
          return hdrs
        end

        def create_authorization_signature(cmd, url, hdrs)
          base_url = url.index('?') ? url[0..(url.index('?')-1)] : url
          to_sign = "#{cmd}\n\n#{hdrs['Content-type']}\n#{hdrs['Date']}\n#{base_url}"
          # puts to_sign
          signature = Base64.encode64(OpenSSL::HMAC.digest(OpenSSL::Digest::Digest.new('sha1'), secret_access_key, to_sign)).strip
          return "AWS #{access_key_id}:#{signature}"
        end

        def http_request_factory(cmd, url, headers, body)
          case cmd
          when 'GET' then Net::HTTP::Get.new(url,headers)
          when 'DELETE' then Net::HTTP::Delete.new(url,headers)
          when 'POST'
              req = Net::HTTP::Post.new(url,headers)
              req.body=body
              req
          when 'PUT'
              req = Net::HTTP::Put.new(url,headers)
              req.body=body
              req
          else raise 'Unsupported http request type'
          end
        end

        def check_errors(response)
          raise response.errors if (response && response.errors?)
          response
        end
        
        def validate_queue_name qn
          raise "Queue name, #{qn}, must be between #{QUEUE_NAME.min} and #{QUEUE_NAME.max} characters." unless QUEUE_NAME.include?(qn.length)
          raise "Queue name, #{qn}, must be alphanumeric only." if (qn =~ /\W/ )
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

        def validate_number_of_messages nom
          raise "Number of messages, #{nom}, must be between #{NUMBER_OF_MESSAGES.min} and #{NUMBER_OF_MESSAGES.max}." unless NUMBER_OF_MESSAGES.include?(nom)
        end

      end

      class SQSResponse
        attr_accessor :headers, :doc, :http_response
        
        def initialize response
          @http_response = response
          @headers = response.to_hash()
          @doc = REXML::Document.new(response.body) if response.kind_of?(Net::HTTPSuccess)
        end
      
        def message_type
          return doc ? doc.root.name : ''
        end

        def errors?
          (not http_response.kind_of?(Net::HTTPSuccess)) or (message_type == "Response")
        end

        def errors
          msg = ""
          if http_response.kind_of?(Net::HTTPSuccess)
            msg = "Errors: "
            each_node('/Response/Errors/Error') { |n|
              c = n.elements['Code'].text
              m = n.elements['Message'].text
              msg << ", " if msg != "Errors: "
              msg << "#{c} : #{m}"
            }
          else
            msg = "HTTP Error: #{http_response.code} : #{http_response.message}"
          end
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

      class Queue
        attr_accessor :name, :pathinfo, :domain, :visibility_timeout

        def self.from_url url
          return Queue.new($3,$2,$1) if url =~ /^http:\/\/(.+)\/(.+)\/(\w+)$/
          raise "Bad Queue URL: #{url}"
        end

        def queue_url
          "/#{pathinfo}/#{name}"
        end

        def initialize name, pathinfo, domain, vt=nil
          @name, @pathinfo, @domain, @visibility_timeout = name, pathinfo, domain, vt
        end

        def to_s
          "<AmazonSQS::Queue name='#{name}' url='#{queue_url}' domain='#{domain}'>"
        end
      end

      # based on stomp message, has pointer to the SQSResponseObject
      class Message
        attr_accessor :headers, :id, :body, :command, :response, :queue
        
        def self.from_element e, response, queue
          Message.new(response.headers, e.elements['MessageId'].text, e.elements['MessageBody'].text, response, queue)
        end
      
        def initialize headers, id, body, response, queue, command='MESSAGE'
          @headers, @id, @body, @response, @queue, @command =  headers, id, body, response, queue, command
          headers['destination'] = queue.name
        end
      
        def to_s
          "<AmazonSQS::Message id='#{id}' body='#{body}' headers='#{headers.inspect}' command='#{command}' response='#{response}'>"
        end
      end
   
    end
  end
end