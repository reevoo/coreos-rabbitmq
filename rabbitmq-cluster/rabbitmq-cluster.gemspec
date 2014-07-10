# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'rabbitmq/cluster/version'

Gem::Specification.new do |spec|
  spec.name          = "rabbitmq-cluster"
  spec.version       = Rabbitmq::Cluster::VERSION
  spec.authors       = ["Ed Robinson"]
  spec.email         = ["ed.robinson@reevoo.com"]
  spec.summary       = %q{ Manages rabbitmq-server within a CoreOS cluster }
  spec.description   = %q{ etcd based cluster discovery for rabbitmq }
  spec.homepage      = ""
  spec.license       = "MIT"

  spec.files         = `git ls-files -z`.split("\x0")
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_dependency 'rabbitmq_manager'
  spec.add_dependency 'etcd-rb'

  spec.add_development_dependency "bundler", "~> 1.5"
  spec.add_development_dependency "rake"
  spec.add_development_dependency "rspec"
end
