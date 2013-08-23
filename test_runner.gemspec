# encoding: utf-8
def self.add_to_path path
 path = File.expand_path "../#{path}/", __FILE__

 $:.unshift path unless $:.include? path
end

add_to_path 'lib'

require 'test_runner/version'

Gem::Specification.new do |s|
  # 1.8.x is not supported
  s.required_ruby_version = '>= 1.9.3'

  s.name = 'test_runner'
  s.version = TestRunner::VERSION
  s.date = TestRunner::DATE
  s.license = 'http://www.apache.org/licenses/LICENSE-2.0.txt'
  s.description = s.summary = 'TestRunner'
  s.description += '.' # avoid identical warning
  s.authors = s.email = [ 'code@bootstraponline.com' ]
  s.homepage = 'https://github.com/appium/test_runner'
  s.require_paths = [ 'lib' ]

  s.add_runtime_dependency 'appium_lib', '= 0.6.7'
  s.add_runtime_dependency 'spec', '= 5.0.19'

  s.files = `git ls-files`.split "\n"
end