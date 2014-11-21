# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'bluenode/version'

Gem::Specification.new do |spec|
  spec.name          = 'bluenode'
  spec.version       = Bluenode::VERSION
  spec.authors       = ['Martin Andert']
  spec.email         = ['mandert@gmail.com']
  spec.summary       = 'A subset of Node.js running in therubyracer.'
  spec.description   = 'A subset of Node.js running in therubyracer.'
  spec.homepage      = 'https://github.com/martinandert/bluenode'
  spec.license       = 'MIT'

  spec.files         = `git ls-files -z`.split("\x0")
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ['lib']

  spec.add_development_dependency 'bundler', '~> 1.7'
  spec.add_development_dependency 'rake', '~> 10.0'

  spec.add_dependency 'therubyracer', '~> 0.12.1'
  spec.add_dependency 'ref'
end
