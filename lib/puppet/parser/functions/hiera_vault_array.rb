require 'hiera_puppet'
require 'hiera_vault'

module Puppet::Parser::Functions
  newfunction(:hiera_vault_array, :type => :rvalue, :arity => -2, :doc => "Performs a
  hiera_array lookup, first and optionally only in the 'vault' backend.

  The behavior depends on the 'override' parameter.

  NOTICE: For this function to work properly, set :override_behavior: 'flag' in the
  :vault: config part in the hiera config.
  ") do |*args|
    key, default, override = HieraPuppet.parse_args(args)
    HieraVault.lookup(key, default, self, override, :array)
  end
end

