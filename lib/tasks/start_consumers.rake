namespace "activemessaging" do

  desc 'Run all consumers'
  task :start_consumers do
    load File.join(File.dirname(__FILE__), '..', '..', 'poller.rb')
  end
  
end
