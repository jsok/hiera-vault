require 'hiera_puppet'
require 'hiera/backend/vault_backend'

module HieraVault
  module_function

  def lookup(key, default, scope, override, resolution_type)
    @hiera_config ||= HieraPuppet.hiera_config
    if not (@hiera_config.has_key?(:backends) and @hiera_config[:backends].include?('vault') and @hiera_config.has_key?(:vault))
      raise(Puppet::ParseError, "hiera_vault: vault backend not configured in hiera config")
    end

    @vault_config ||= @hiera_config[:vault]
    if not (@vault_config.has_key?(:override_behavior) and @vault_config[:override_behavior] == 'flag')
      raise(Puppet::ParseError, "hiera_vault: :override_behavior needs to be set to 'flag' in hiera config")
    end

    flag_default = 'vault'
    if @vault_config.has_key?(:flag_default)
      flag_default = @vault_config[:flag_default]
      if not ['vault','vault_only'].include?(flag_default)
        raise(Puppet::ParseError, "hiera_vault: invalid value '#{flag_default}' for :flag_default in hiera config, one of 'vault', 'vault_only' expected")
      end
    end

    override ||= {'flag' => flag_default}
    case override.class.to_s
    when 'String'
      override = {'flag' => flag_default, 'override' => override}
    when 'Hash'
      if not override.has_key?('flag')
        override['flag'] = flag_default
      end
    else
      raise(Puppet::ParseError, "hiera_vault: invalid 'override' parameter supplied: '#{override}':#{override.class}")
    end

    if resolution_type == :priority
      if default.kind_of? Hash
        if default.has_key?('generate')
          if @vault_config[:default_field]
            override['generate'] = default['generate'].to_i
            default = nil
          end
        end
      end
    end

    # this part is needed, since the 'default' parameter is not available in backends
    @vault_backend ||= Hiera::Backend::Vault_backend.new
    hiera_scope = Hiera::Scope.new(scope)
    new_answer = @vault_backend.lookup(key, hiera_scope, override, resolution_type)
    if new_answer.nil?
      answer = new_answer
    else
      case resolution_type
      when :array
        raise Exception, "hiera_vault: after vault_backend.lookup: type mismatch: expected Array and got #{new_answer.class}" unless new_answer.kind_of? Array or new_answer.kind_of? String
        answer ||= []
        answer << new_answer
      when :hash
        raise Exception, "hiera_vault: after vault_backend.lookup: type mismatch: expected Hash and got #{new_answer.class}" unless new_answer.kind_of? Hash
        answer ||= {}
        answer = Hiera::Backend.merge_answer(new_answer,answer)
      else
        answer = new_answer
      end
    end

    if override['flag'] == 'vault_only'
      if not (default.nil? or default.empty?)
        answer = Hiera::Backend.resolve_answer(answer, resolution_type) unless answer.nil?
        answer = Hiera::Backend.parse_string(default, hiera_scope) if answer.nil? and default.is_a?(String)
        answer = default if answer.nil?
      end
      if answer.nil?
        raise(Puppet::ParseError, "hiera_vault: Could not find data item #{key} in vault, while vault_only was requested, and empty default supplied")
      end
      return answer
    end

    if answer.nil? or resolution_type != :priority
      # continue with normal hiera lookup, while vault_backend will skip automatically
      if override.has_key?('override')
        override = override['override']
      else
        override = nil
      end

      begin
        new_answer = HieraPuppet.lookup(key, nil, scope, override, resolution_type)
      rescue Puppet::ParseError
        if default.nil? or default.empty?
          raise(Puppet::ParseError, "Could not find data item #{key} in vault and in any Hiera data file and no or empty default supplied")
        end
        answer = Hiera::Backend.parse_string(default, hiera_scope) if default.is_a?(String)
        answer = default if answer.nil?
        return answer
      end
    end
    case resolution_type
    when :array
      raise Exception, "hiera_vault: after normal Hiera lookup: type mismatch: expected Array and got #{new_answer.class}" unless new_answer.nil? or new_answer.kind_of? Array or new_answer.kind_of? String
      answer ||= []
      answer << new_answer
    when :hash
      raise Exception, "hiera_vault: after normal Hiera lookup: type mismatch: expected Hash and got #{new_answer.class}" unless new_answer.kind_of? Hash
      answer ||= {}
      answer = Hiera::Backend.merge_answer(new_answer,answer)
    else
      answer = new_answer
    end
    answer = Hiera::Backend.resolve_answer(answer, resolution_type)
    return answer
  end

end

