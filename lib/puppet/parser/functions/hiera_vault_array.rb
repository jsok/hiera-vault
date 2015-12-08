require 'hiera_puppet'
require 'hiera/backend/vault_backend'

module Puppet::Parser::Functions
  newfunction(:hiera_vault_array, :type => :rvalue, :arity => -2, :doc => "Performs a
  hiera_array lookup, first and optionally only in the 'vault' backend.

  The behavior depends on the 'override' parameter.

  NOTICE: For this function to work properly, set :override_behavior: 'flag' in the
  :vault: config part in the hiera config.
  ") do |*args|
    @hiera_config ||= HieraPuppet.hiera_config
    if not (@hiera_config.has_key?(:backends) and @hiera_config[:backends].include?('vault') and @hiera_config.has_key?(:vault))
      raise(Puppet::ParseError, "hiera_vault: vault backend not configured in hiera config")
    end

    @vault_config ||= @hiera_config[:vault]
    if not (@vault_config.has_key?(:override_behavior) and @vault_config[:override_behavior] == 'flag')
      raise(Puppet::ParseError, "hiera_vault :vault::override_behavior needs to be set to 'flag' in hiera config")
    end

    flag_default = 'vault'
    if @vault_config.has_key?(:flag_default)
      flag_default = @vault_config[:flag_default]
      if not ['vault','vault_only'].include?(flag_default)
        raise(Puppet::ParseError, "hiera_vault: invalid value '#{flag_default}' for :flag_default in hiera config, one of 'vault', 'vault_only' expected")
      end
    end

    key, default, override = HieraPuppet.parse_args(args)
    override ||= {'flag' => flag_default}
    case override.class.to_s
    when 'String'
      override = {'flag' => flag_default, 'override' => override}
    when 'Hash'
      if not override.has_key?('flag')
        override['flag'] = flag_default
      end
    else
      raise(Puppet::ParseError, "hiera_vault: invalid 'override' parameter supplied: #{override}:#{override.class}")
    end
    # this part is needed, since the 'default' parameter is not available in backends
    @vault_backend ||= Hiera::Backend::Vault_backend.new
    scope = Hiera::Scope.new(self)
    new_answer = @vault_backend.lookup(key, scope, override, :array)
    if new_answer.nil?
      answer = new_answer
    else
      raise Exception, "hiera_vault_array: after vault_backend.lookup: type mismatch: expected Array and got #{new_answer.class}" unless new_answer.kind_of? Array or new_answer.kind_of? String
      answer ||= []
      answer << new_answer
    end
    if override['flag'] == 'vault_only'
      if not (default.nil? or default.empty?)
        answer = Hiera::Backend.resolve_answer(answer, :array) unless answer.nil?
        answer = Hiera::Backend.parse_string(default, scope) if answer.nil? and default.is_a?(String)
        answer = default if answer.nil?
      end
      if answer.nil?
        raise(Puppet::ParseError, "hiera_vault_array: Could not find data item #{key} in vault, while vault_only was requested, and empty default supplied")
      end
      return answer
    end
    # continue with other backends using normal hiera_array call, vault backend will be skipped automatically
    if override.has_key?('override')
      override = override['override']
    else
      override = nil
    end
    begin
      new_answer = HieraPuppet.lookup(key, nil, self, override, :array)
    rescue Puppet::ParseError
      answer = Hiera::Backend.parse_string(default, scope) if default.is_a?(String)
      answer = default if answer.nil?
      return answer
    end
    raise Exception, "hiera_vault_array after normal Hiera lookup: type mismatch: expected Array and got #{new_answer.class}" unless new_answer.nil? or new_answer.kind_of? Array or new_answer.kind_of? String
    answer ||= []
    answer << new_answer
    answer = Hiera::Backend.resolve_answer(answer, :array)
    return answer
  end
end
