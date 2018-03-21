# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'activemessaging/version'

Gem::Specification.new do |spec|
  spec.name          = "activemessaging"
  spec.version       = ActiveMessaging::VERSION
  spec.authors       = ["Andrew Kuklewicz", "Jon Tirsen", "Olle Jonsson", "Sylvain Perez", "Cliff Moon", "Uwe Kubosch", "Lance Cooper", "Matt Campbell"]
  spec.email         = ["activemessaging-discuss@googlegroups.com"]
  spec.description   = "ActiveMessaging is an attempt to bring the simplicity and elegance of Rails development to the world of messaging. Messaging, (or event-driven architecture) is widely used for enterprise integration, with frameworks such as Java's JMS, and products such as ActiveMQ, Tibco, IBM MQSeries, etc."
  spec.summary       = "ActiveMessaging is an attempt to bring the simplicity and elegance of Rails development to the world of messaging."
  spec.homepage      = "http://github.com/kookster/activemessaging"
  spec.license       = "MIT"

  spec.files         = `git ls-files`.split($/)
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_runtime_dependency 'activesupport'
  spec.add_runtime_dependency 'celluloid'

  spec.add_development_dependency 'bundler', '~> 1.3'
  spec.add_development_dependency 'rake'
  spec.add_development_dependency 'appraisal'

  spec.add_development_dependency 'minitest'
  spec.add_development_dependency 'webmock'
  spec.add_development_dependency 'pry'

  spec.add_development_dependency 'guard'
  spec.add_development_dependency 'guard-bundler'
  spec.add_development_dependency 'guard-minitest'

  spec.add_development_dependency 'simplecov'
  spec.add_development_dependency 'coveralls'
end
