require 'activemessaging/adapters/base'
# 
# This is meant to avoid the need to use a broker in development, and generally make development mode easier
# 
module ActiveMessaging
  module Adapters
    module Synch
    
      class Connection  < ActiveMessaging::Adapters::BaseConnection
        register :synch

        #configurable params
        attr_accessor :configuration, :max_process, :processing_pids, :use_fork

        #generic init method needed by a13g
        def initialize cfg
          ActiveMessaging.logger.debug "ActiveMessaging::Adapters::Synch::Connection.initialize: #{cfg.inspect}"
          @configuration = cfg
          
          @use_fork = !!@configuration[:use_fork]

          # max at once
          @max_process = 10
          # keep track of the processes running
          @processing_pids = {}

          if use_fork
            Thread.new {
              watch_processes
            }
          end
        end
        
        def watch_processes
          while true
            begin
              pid = Process.wait(0, Process::WNOHANG)
              if m = processing_pids.delete(pid)
                ActiveMessaging.logger.debug "ActiveMessaging:synch - processing complete for pid (#{pid}):\n\t#{m}"
              end
              sleep(0.5)
            rescue
            end
          end
        end

        def send destination_name, message_body, message_headers={}
          message = Message.new(message_body, 'id', message_headers, destination_name, 'MESSAGE')
          
          if use_fork

            if processing_pids.size > max_process
              ActiveMessaging.logger.debug "ActiveMessaging:synch too many processes: #{processing_pids.size} > #{max_process}"
              sleep(0.5)
            end

            pid = fork {
              ActiveMessaging.logger.debug "\n-------------------- ActiveMessaging:synch start fork dispath (#{Process.pid}) --------------------"
              ActiveMessaging::Gateway.prepare_application
              ActiveMessaging::Gateway._dispatch(message)
              ActiveMessaging::Gateway.reset_application
              ActiveMessaging.logger.debug "-------------------- ActiveMessaging:synch end fork dispath (#{Process.pid})--------------------\n"
            }

            Process.detach(pid)
            processing_pids[pid] = "Destination: #{destination_name}, Message: #{message_body}"

          else

            ActiveMessaging.logger.debug "\n-------------------- ActiveMessaging:synch before dispath --------------------"
            ActiveMessaging::Gateway.prepare_application
            ActiveMessaging::Gateway._dispatch(message)
            ActiveMessaging::Gateway.reset_application
            ActiveMessaging.logger.debug "-------------------- ActiveMessaging:synch after dispath --------------------\n"

          end
          
        end

      end

      class Message < ActiveMessaging::BaseMessage
        attr_accessor :command

        def initialize body, id, headers, destination, command='MESSAGE'
          # ActiveMessaging.logger.debug "Message headers:#{headers.inspect}, id:#{id}, body:#{body}, destination:#{destination}, command:#{command}"
          @headers, @body, @destination, @command =  headers, body, destination, command
          headers['destination'] = destination
        end

      end
    
    end
  end
end
