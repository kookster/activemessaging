class <%= class_name %>Controller < ApplicationController
  include ActiveMessaging::MessageSender
  
  publishes_to :trace

  def index
  end

  def clear
    publish :trace, "<trace-control>clear</trace-control>"
    redirect_to :action=>'index'
  end

end
