require 'rubygems'
require 'rubygems/package_task'

spec = Gem::Specification.new do |gem|
    gem.name = "hiera-vault"
    gem.version = "0.1.6.pre1"
    gem.license = "Apache-2.0"
    gem.summary = "Module for using vault as a hiera backend"
    gem.email = "jonathan.sokolowski@gmail.com"
    gem.authors = ["Jonathan Sokolowski", "Arnoud Witt"]
    gem.homepage = "http://github.com/jsok/hiera-vault"
    gem.description = "Hiera backend for looking up secrets stored in Vault"
    gem.require_path = "lib"
    gem.files = FileList["lib/**/*"].to_a
    gem.add_dependency('vault', '~> 0.1', '>= 0.1.5')
end
