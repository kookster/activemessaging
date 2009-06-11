require 'rake'
require 'rake/testtask'
require 'rdoc/rdoc'
require 'rake/gempackagetask'

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

gem_spec = Gem::Specification.new do |s|
  s.name = %q{activemessaging}
  s.version = "0.6.1"

  s.specification_version = 2 if s.respond_to? :specification_version=

  s.required_rubygems_version = Gem::Requirement.new(">= 0") if s.respond_to? :required_rubygems_version=
  s.authors = ["jon.tirsen", "kookster", "olle.jonsson", "sylvain.perez", "anti.god.botherer", 'uwe.kubosch']
  s.date = %q{2008-08-15}
  s.description = %q{ActiveMessaging is an attempt to bring the simplicity and elegance of rails development to the world of messaging. Messaging, (or event-driven architecture) is widely used for enterprise integration, with frameworks such as Java's JMS, and products such as ActiveMQ, Tibco, IBM MQSeries, etc.}
  s.email = %q{activemessaging-discuss@googlegroups.com}
  s.files = FileList['generators/**/*', 'lib/**/*', 'tasks/**/*', 'Rakefile', 'messaging.rb.example'].to_a
  s.homepage = %q{http://code.google.com/p/activemessaging/}
  s.require_paths = ["lib"]
  s.rubygems_version = %q{1.2.0}
  s.summary = %q{ActiveMessaging is an attempt to bring the simplicity and elegance of rails development to the world of messaging. Messaging, (or event-driven architecture) is widely used for enterprise integration, with frameworks such as Java's JMS, and products such as ActiveMQ, Tibco, IBM MQSeries, etc.}
  #s.test_files = ["test"]
  #s.autorequire = 'activemessaging'
  s.has_rdoc = true

  s.add_dependency(%q<activesupport>, [">= 1.0.0"])
  s.add_dependency(%q<rubigen>, [">= 1.5.2"])
  #s.add_dependency(%q<common-pool-cliffmoon>, [">= 0.0.3"])
end

desc 'Generate ActiveMessaging gem.'
Rake::GemPackageTask.new(gem_spec) do |pkg|
end

