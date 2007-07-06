class ActiveMessagingTestController < ApplicationController

  include ActiveMessaging::MessageSender

  def index
    @destinations = ActiveMessaging::Gateway.named_destinations.values

    if request.post?
      @message = params[:message]

      if params[:destination].nil? || params[:destination].empty?
        flash[:notice] = "Please specify a destination."
        return
      else
        @destination = params[:destination].intern
      end

      if @message.nil? || @message.empty?
        flash[:notice] = "Please specify a message."
        return
      end

      puts "#{@destination} : #{@message}"
      publish @destination, @message
      flash[:notice] = "'#{@message}' sent to #{@destination}"
    end
  end

end
