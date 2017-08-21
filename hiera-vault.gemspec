require 'rubygems'
require 'rubygems/package_task'

spec = Gem::Specification.new do |gem|
    gem.name = "hiera-vault"
    gem.version = "0.2.2.1"
    gem.license = "Apache-2.0"
    gem.summary = "Module for using vault as a hiera backend"
    gem.email = "jonathan.sokolowski@gmail.com"
    gem.author = "Jonathan Sokolowski"
    gem.homepage = "http://github.com/jsok/hiera-vault"
    gem.description = "Hiera backend for looking up secrets stored in Vault"
    gem.require_path = "lib"
    gem.files = FileList["lib/**/*"].to_a
    gem.add_dependency('vault', '~> 0.4')
end
