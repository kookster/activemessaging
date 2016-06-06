#!/usr/bin/env ruby
# Make sure stdout and stderr write out without delay for using with daemon like scripts
STDOUT.sync = true; STDOUT.flush
STDERR.sync = true; STDERR.flush

load File.join(Rails.root, 'config', 'environment.rb')

# Start it up!
ActiveMessaging::start
