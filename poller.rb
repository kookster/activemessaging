#!/usr/bin/env ruby
# Make sure stdout and stderr write out without delay for using with daemon like scripts
STDOUT.sync = true; STDOUT.flush
STDERR.sync = true; STDERR.flush

# Load Rails
RAILS_ROOT=File.expand_path(File.join(File.dirname(__FILE__), '..','..','..'))
load File.join(RAILS_ROOT, 'config', 'environment.rb')

# Load ActiveMessaging
ActiveMessaging::load_activemessaging

# Start it up!
ActiveMessaging::start
