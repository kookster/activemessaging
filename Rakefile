require 'rubygems'
require 'bundler/setup'

require 'rake'
require 'rake/testtask'
require 'rdoc/rdoc'

require 'appraisal'

desc 'Default: run unit tests.'
task :default => :test

desc 'Test the ActiveMessaging plugin.'
Rake::TestTask.new(:test) do |t|
  t.libs << 'lib'
  t.pattern = 'test/**/*_test.rb'
  t.verbose = true
end

desc 'Generate documentation for the ActiveMessaging plugin.'
task :rdoc do
  rm_rf 'doc'
  RDoc::RDoc.new.document(%w(--line-numbers --inline-source --title ActiveMessaging README lib))
end

begin
  require 'jeweler'
  Jeweler::Tasks.new do |gemspec|
    
    # basic
    gemspec.name = "activemessaging"
    gemspec.summary = "Official activemessaging gem, now hosted on github.com/kookster. (kookster prefix temporary)"
    gemspec.description = "ActiveMessaging is an attempt to bring the simplicity and elegance of rails development to the world of messaging. Messaging, (or event-driven architecture) is widely used for enterprise integration, with frameworks such as Java's JMS, and products such as ActiveMQ, Tibco, IBM MQSeries, etc. Now supporting Rails 3 as of version 0.8.0."
    gemspec.email = "activemessaging-discuss@googlegroups.com"
    gemspec.homepage = "http://github.com/kookster/activemessaging"
    gemspec.authors = ["Jon Tirsen", "Andrew Kuklewicz", "Olle Jonsson", "Sylvain Perez", "Cliff Moon", 'Uwe Kubosch', 'Lance Cooper', 'Matt Campbell']

    # added
    gemspec.add_dependency('activesupport', '>= 2.3.11')

    gemspec.add_development_dependency('jeweler')
    gemspec.add_development_dependency('stomp')
    gemspec.add_development_dependency('appraisal')

  end
  Jeweler::GemcutterTasks.new
rescue LoadError
  puts "Jeweler not available. Install it with: gem install jeweler"
end
