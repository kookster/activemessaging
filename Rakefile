require 'rake'
require 'rake/testtask'
require 'rdoc/rdoc'

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
