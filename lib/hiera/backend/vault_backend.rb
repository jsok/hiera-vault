# Vault backend for Hiera
class Hiera
  module Backend
    class Vault_backend

      def initialize()
        require 'json'
        require 'vault'
        Hiera.debug("Hiera VAULT backend starting")

        @config = Config[:vault]
        @config[:mounts] ||= {}
        @config[:mounts][:generic] ||= ['secret']
        @config[:default_field_parse] ||= 'string' # valid values: 'string', 'json'

        # :override_behavior:
        # Valid values: 'normal', 'flag'
        # Default: 'normal'
        # If set to 'flag' a read from vault will only be done if the override parameter
        # is a hash, and it contains the 'flag', it will behave like this:
        # - when the value of the 'flag' key is 'vault', it will look in vault
        # - when the value is 'vault_only', it will return the default or raise an exception
        #   if the lookup key is not found in vault
        # If the 'flag' key does not exist, or if the override parameter is not a hash,
        # nil will be returned to signal that the next backend should be searched.
        # If the hash contains the 'override' key, its value will be used as the actual
        # override.
        # To support the 'flag' behavior, the `hiera_vault`, `hiera_vault_array`, and
        # `hiera_vault_hash` functions need to be used, since they will make sure the
        # override parameter is checked and changed where needed
        # Additionally, when 'vault_only' is used, it will only work properly using the
        # special hiera_vault* functions
        #
        # The 'flag_default' setting can be used to set the default for the 'flag' element
        # to 'vault_only'. This is handled by the hiera_vault* parser functions.
        #
        @config[:override_behavior] ||= 'normal'
        if not ['normal','flag'].include?(@config[:override_behavior])
          raise Exception, "[hiera-vault] invalid value for :override_behavior: '#{@config[:override_behavior]}', should be one of 'normal','flag'"
        end

        @config[:flag_default] ||= 'vault_first'
        if not ['vault_first','vault_only'].include?(@config[:flag_default])
          raise Exception, "hiera_vault: invalid value '#{@config[:flag_default]}' for :flag_default in hiera config, one of 'vault_first', 'vault_only' expected"
        end

        @config[:default_field_parse] ||= 'string' # valid values: 'string', 'json'
        if not ['string','json'].include?(@config[:default_field_parse])
          raise Exception, "[hiera-vault] invalid value for :default_field_parse: '#{@config[:default_field_behavior]}', should be one of 'string','json'"
        end

        # :default_field_behavior:
        #   'ignore' => ignore additional fields, if the field is not present return nil
        #   'only'   => only return value of default_field when it is present and the only field, otherwise return hash as normal
        @config[:default_field_behavior] ||= 'ignore'
        if not ['ignore','only'].include?(@config[:default_field_behavior])
          raise Exception, "[hiera-vault] invalid value for :default_field_behavior: '#{@config[:default_field_behavior]}', should be one of 'ignore','only'"
        end

        vault_connect
      end

      def lookup(key, scope, order_override, resolution_type)
        begin
          vault_connect

          read_vault = false
          genpw = false
          otp = nil

          if @config[:override_behavior] == 'flag'
            if order_override.kind_of? Hash
              if order_override.has_key?('flag')
                if ['vault_default','vault_first','vault_only'].include?(order_override['flag'])
                  read_vault = true
                  if order_override['flag'] == 'vault_default'
                    # since variables are passed by reference, the caller will know afterwards, which flag was actually used
                    order_override['flag'] = @config[:flag_default]
                  end
                  if order_override.has_key?('generate')
                    pwlen = order_override['generate'].to_i
                    if pwlen > 8 # TODO: make configurable
                      genpw = true
                    end
                  end
                  if order_override.has_key?('vault_otp')
                    otp = order_override['vault_otp']
                  end
                  if order_override.has_key?('resolution_type')
                    resolution_type = order_override['resolution_type']
                  end
                  # this one must be last, because order_override gets a new value!:
                  if order_override.has_key?('override')
                    order_override = order_override['override']
                  else
                    order_override = nil
                  end
                else
                  raise Exception, "[hiera-vault] Invalid value '#{order_override['flag']}' for 'flag' element in override parameter, expected one of ['vault_default', 'vault_first', 'vault_only'], while override_behavior is 'flag'"
                end
                if @vault.nil?
                  raise Exception, "[hiera-vault] Cannot skip, because vault is unavailable and vault must be read, while override_behavior is 'flag'"
                end
              else
                Hiera.debug("[hiera-vault] Not reading from vault, because 'flag' element does not exist in override parameter, while override_behavior is 'flag'")
              end
            else
              Hiera.debug("[hiera-vault] Not reading from vault, because override parameter is not a hash, while override_behavior is 'flag'")
            end
          else
            # normal behavior
            return nil if @vault.nil?
            read_vault = true
          end

          answer = nil

          if read_vault
            Hiera.debug("[hiera-vault] Looking up #{key} in vault backend")

            found = false

            # Only generic mounts supported so far
            @config[:mounts][:generic].each do |mount|
              path = Backend.parse_string(mount, scope, { 'key' => key })
              Backend.datasources(scope, order_override) do |source|
                Hiera.debug("Looking in path #{path}/#{source}/")
                new_answer = lookup_generic("#{path}/#{source}/#{key}", scope)
                #Hiera.debug("[hiera-vault] Answer: #{new_answer}:#{new_answer.class}")
                next if new_answer.nil?
                case resolution_type
                when :array
                  raise Exception, "Hiera type mismatch: expected Array and got #{new_answer.class}" unless new_answer.kind_of? Array or new_answer.kind_of? String
                  answer ||= []
                  answer << new_answer
                when :hash
                  raise Exception, "Hiera type mismatch: expected Hash and got #{new_answer.class}" unless new_answer.kind_of? Hash
                  answer ||= {}
                  answer = Backend.merge_answer(new_answer,answer)
                else
                  answer = new_answer
                  found = true
                  break
                end
              end

              break if found
            end
          end

          if answer.nil? and @config[:default_field] and genpw
            new_answer = generate(pwlen)

            @config[:mounts][:generic].each do |mount|
              path = Backend.parse_string(mount, scope, { 'key' => key })
              Backend.datasources(scope, order_override) do |source|
                # Storing the generated secret in the override path or the highest path in the hierarchy
                # make sure to use a proper override or an appropriate hierarchy if the secret is to be used
                # on different nodes, otherwise the same key might be written with a different value at different
                # paths
                Hiera.debug("Storing generated secret in vault at path #{path}/#{source}/#{key}")
                answer = new_answer if store("#{path}/#{source}/#{key}", { @config[:default_field].to_sym => new_answer })
                break
              end
              break
            end
          end
          if answer.nil? and not otp.nil?
            answer = otp
          end
          return answer
        rescue Exception => e
          raise Exception, "#{e.message} in #{e.backtrace[0]}"
        end
      end

      def vault_connect
        if @vault.nil?
          begin
            @vault = Vault::Client.new
            @vault.configure do |config|
              config.address = @config[:addr] if @config[:addr]
              config.token = @config[:token] if @config[:token]
              config.ssl_pem_file = @config[:ssl_pem_file] if @config[:ssl_pem_file]
              config.ssl_verify = @config[:ssl_verify] if @config[:ssl_verify]
              config.ssl_ca_cert = @config[:ssl_ca_cert] if config.respond_to? :ssl_ca_cert
              config.ssl_ca_path = @config[:ssl_ca_path] if config.respond_to? :ssl_ca_path
              config.ssl_ciphers = @config[:ssl_ciphers] if config.respond_to? :ssl_ciphers
            end

            fail if @vault.sys.seal_status.sealed?
            Hiera.debug("[hiera-vault] Client configured to connect to #{@vault.address}")
          rescue Exception => e
            @vault = nil
            Hiera.warn("[hiera-vault] Skipping backend. Configuration error: #{e}")
          end
        end
        if @vault
          begin
            fail if @vault.sys.seal_status.sealed?
          rescue Exception => e
            @vault = nil
            Hiera.warn("[hiera-vault] Vault is unavailable or configuration error: #{e}")
          end
        end
      end

      def lookup_generic(key, scope)
          begin
            secret = @vault.logical.read(key)
          rescue Exception => e
            raise Exception, "[hiera-vault] Could not read secret #{key}, #{e.class}: #{e.errors.join("\n").rstrip}"
          end

          return nil if secret.nil?

          Hiera.debug("[hiera-vault] Read secret: #{key}")
          if @config[:default_field] and (@config[:default_field_behavior] == 'ignore' or (secret.data.has_key?(@config[:default_field].to_sym) and secret.data.length == 1))
            return nil if not secret.data.has_key?(@config[:default_field].to_sym)
            # Return just our default_field
            data = secret.data[@config[:default_field].to_sym]
            if @config[:default_field_parse] == 'json'
              begin
                data = JSON.parse(data)
              rescue JSON::ParserError
                Hiera.debug("[hiera-vault] Could not parse string as JSON")
              end
            end
          else
            # Turn secret's hash keys into strings
            data = secret.data.inject({}) { |h, (k, v)| h[k.to_s] = v; h }
          end
          #Hiera.debug("[hiera-vault] Data: #{data}:#{data.class}")

          return Backend.parse_answer(data, scope)
      end

      def generate(password_size)
        pass = ""
        (1..password_size).each do
          pass += (("a".."z").to_a+("A".."Z").to_a+("0".."9").to_a)[rand(62).to_int]
        end

        pass
      end

      def store(key, secret_hash)
          begin
            write_result = @vault.logical.write(key, secret_hash)
          rescue Vault::HTTPConnectionError
            Hiera.debug("[hiera-vault] Could not connect to write secret: #{key}")
          rescue Vault::HTTPError => e
            Hiera.warn("[hiera-vault] Could not write secret #{key}: #{e.errors.join("\n").rstrip}")
          end

          if write_result == true
            Hiera.debug("[hiera-vault] Successfully written secret: #{key}")
            return true
          else
            Hiera.warn("[hiera-vault] Could not write secret #{key}: #{write_result}")
            return false
          end
      end

    end
  end
end
