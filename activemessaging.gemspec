# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'activemessaging/version'

Gem::Specification.new do |spec|
  spec.name = "activemessaging"
  spec.version = ActiveMessaging::VERSION
  spec.authors = ["Jon Tirsen", "Andrew Kuklewicz", "Olle Jonsson", "Sylvain Perez", "Cliff Moon", "Uwe Kubosch", "Lance Cooper", "Matt Campbell"]
  spec.email = ["activemessaging-discuss@googlegroups.com"]

  spec.summary = "Official activemessaging gem, now hosted on github.com/kookster. (kookster prefix temporary)"
  spec.description = "ActiveMessaging is an attempt to bring the simplicity and elegance of rails development to the world of messaging. Messaging, (or event-driven architecture) is widely used for enterprise integration, with frameworks such as Java's JMS, and products such as ActiveMQ, Tibco, IBM MQSeries, etc. Now supporting Rails 3 as of version 0.8.0."
  spec.homepage = "http://github.com/kookster/activemessaging"
  spec.license       = "MIT"

  spec.files         = `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler"
  spec.add_development_dependency "rake"
  spec.add_development_dependency "test-unit"
  spec.add_development_dependency "stomp"

  spec.add_runtime_dependency "activesupport"
end
