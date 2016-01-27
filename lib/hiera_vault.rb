require 'hiera_puppet'

module HieraVault

  module_function
  def lookup(key, default, scope, override, resolution_type)
    begin
      flag_default = 'vault_default'
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
            override['generate'] = default['generate'].to_i
            default = nil
          end
        end
      end

      r = rand(2147483647).to_s
      otp = "vault_otp_#{r}"
      case resolution_type
      when :array
        otp = [otp]
      when :hash
        otp = {'otp' => otp}
      end
      override['vault_otp'] = otp

      # this is for vault_backend so that it will use the actual resolution type internally
      override['resolution_type'] = resolution_type

      new_answer = HieraPuppet.lookup(key, nil, scope, override, :priority)
      if new_answer == otp
        # this means that vault_backend could not find anything, so it returned the value of vault_otp
        new_answer = nil
      end

      if new_answer.nil?
        answer = nil
      else
        case resolution_type
        when :array
          raise Puppet::ParseError, "hiera_vault: after vault_backend.lookup: type mismatch: expected Array and got #{new_answer.class}" unless new_answer.kind_of? Array or new_answer.kind_of? String
          answer ||= []
          answer << new_answer
        when :hash
          raise Puppet::ParseError, "hiera_vault: after vault_backend.lookup: type mismatch: expected Hash and got #{new_answer.class}" unless new_answer.kind_of? Hash
          answer ||= {}
          answer = Hiera::Backend.merge_answer(new_answer,answer)
        else
          answer = new_answer
        end
      end

      hiera_scope = Hiera::Scope.new(scope)
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
          if answer.nil?
            if default.nil? or default.empty?
              raise(Puppet::ParseError, "Could not find data item #{key} in vault and in any Hiera data file and no or empty default supplied")
            end
            answer = Hiera::Backend.parse_string(default, hiera_scope) if default.is_a?(String)
            answer = default if answer.nil?
            return answer
          end
        end
      end
      if not new_answer.nil?
        case resolution_type
        when :array
          raise Puppet::ParseError, "hiera_vault: after normal Hiera lookup: type mismatch: expected Array and got #{new_answer.class}" unless new_answer.nil? or new_answer.kind_of? Array or new_answer.kind_of? String
          answer ||= []
          answer << new_answer
        when :hash
          raise Puppet::ParseError, "hiera_vault: after normal Hiera lookup: type mismatch: expected Hash and got #{new_answer.class}" unless new_answer.kind_of? Hash
          answer ||= {}
          answer = Hiera::Backend.merge_answer(new_answer,answer)
        else
          answer = new_answer
        end
      end
      answer = Hiera::Backend.resolve_answer(answer, resolution_type)
      return answer
    rescue Exception => e
      raise(Puppet::ParseError, "#{e.message} in #{e.backtrace[0]}")
    end
  end

end

