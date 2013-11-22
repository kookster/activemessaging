# -*- encoding: utf-8 -*-

require 'simplecov'
require 'coveralls'

SimpleCov.command_name 'Unit Tests'
SimpleCov.formatter = SimpleCov::Formatter::MultiFormatter[
  SimpleCov::Formatter::HTMLFormatter,
  Coveralls::SimpleCov::Formatter
]
SimpleCov.start

require 'minitest/autorun'
require 'minitest/spec'
require 'minitest/mock'
require 'webmock/minitest'

# require 'activemessaging'

rails_environtment_file = File.expand_path(File.dirname(__FILE__) + "/../../../../config/environment")

if File.exists? rails_environtment_file
  require rails_environment_file
  APP_ROOT = RAILS_ROOT
  APP_ENV = Rails.env
else
  ENV['APP_ENV'] = 'test'
  APP_ENV = 'test'
  APP_ROOT = File.dirname(__FILE__) + '/app'
  
  $: << File.expand_path(File.dirname(__FILE__) + '/../lib')
  require 'rubygems'
  require 'active_support/all'

  module ActiveMessaging
    def self.app_root
      APP_ROOT
    end

    def self.app_env
      APP_ENV
    end
  end

  require 'activemessaging/message_sender'
  require 'activemessaging/processor'
  require 'activemessaging/gateway'
  require 'activemessaging/filter'
  require 'activemessaging/adapters/test'
end

require File.dirname(__FILE__) + '/../lib/activemessaging/test_helper'
