#!/usr/bin/env ruby
# Make sure stdout and stderr write out without delay for using with daemon like scripts
STDOUT.sync = true; STDOUT.flush
STDERR.sync = true; STDERR.flush

# The daemons gem sets our cwd to /, which Rails doesn't work well with.
Dir.chdir APP_ROOT

#Try to Load Merb
merb_init_file = File.expand_path(File.dirname(__FILE__)+'/../config/merb_init')
if File.exists? merb_init_file
  require File.expand_path(File.dirname(__FILE__)+'/../config/boot')
  #need this because of the CWD
  Merb.root = MERB_ROOT
  require merb_init_file
else
  # Load Rails
  RAILS_ROOT=File.expand_path(File.join(File.dirname(__FILE__), '..'))
  require File.join(RAILS_ROOT, 'config', 'boot')
  require File.join(RAILS_ROOT, 'config', 'environment')
end

# Start it up!
require 'activemessaging'
ActiveMessaging.load_activemessaging
ActiveMessaging.start
