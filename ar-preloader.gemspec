# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'ar/preloader/version'

Gem::Specification.new do |spec|
  spec.name          = "ar-preloader"
  spec.version       = Ar::Preloader::VERSION
  spec.authors       = ["Ajith Hussain"]
  spec.email         = ["csy0013@googlemail.com"]

  spec.summary       = %q{ar-preloader lets you preload a select list of associations on a specified list of ActiveRecord objects.}
  spec.description   = %q{ar-preloader lets you fetch the selected associations for a list of ActiveRecord objects.}
  spec.homepage      = "https://github.com/sparkymat/ar-preloader"
  spec.license       = "MIT"

  spec.files         = `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency("activerecord", [">= 4.0.0"])
  spec.add_dependency("rusql", [">=  1.0.5"])

  spec.add_development_dependency "bundler", "~> 1.11"
  spec.add_development_dependency "rake", "~> 10.0"
  spec.add_development_dependency "rspec", "~> 3.0"
end
