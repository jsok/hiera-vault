source "http://rubygems.org"

gem "puppet", ENV['PUPPET_VERSION'] || '~> 3.8'
gem "vault", '~> 0.4'
gem "rake", '~> 11.1'

group :development, :test do
  gem 'rspec', "~> 3.3", :require => false
  gem "rspec-legacy_formatters", "~> 1.0", :require => false
  gem 'mocha', "~> 0.10.5", :require => false
end
