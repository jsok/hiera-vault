# Vault backend for Hiera
class Hiera
  # Due to the authentication information might be not avaliable
  # on the moment when the Puppet is runed for the first time, 
  # addig the variable that indicates if the actual authentication
  # already happened.
  # For example if it's the first pupper run ever, the host is not enrolled in
  # the domain yet and there is no Kerberos on this stage but it will 
  # be when someone will actually try to read value from the Vault. At this 
  # moment the actuall authentication would happen.
  # Options for:
  # proto       - protocol (http/htts)
  # port        - port where vault server litens
  # fqdn_expand - short hostname given, expend it
  # auth_type   - if "external", use external command for authentication
  # cmd         - command to run for the authentication. Should just return
  #               tokn in the stdout. Should accept hostname + extra optional
  #               arguments.
  # args        - extra arguments for the command defined in the "cmd"
  initialized = false
  module RunCmd
    module_function

    # @param  [String] cmd   -> command to run
    # @return [String]       -> Stdout
    # @throws [RuntimeError] -> includes the Stderr

    def cmd command
      require 'open3'
      stdout_str, stderr_str, status = Open3.capture3(command)
      fail "#{command}: #{stderr_str.chomp}"  unless status.success?
      stdout_str
    end
  end

  module Backend
    class Vault_backend

      def initialize()
        Hiera.debug("[hiera-vault] backned is loaded")
      end
      def initialize_vault()
        require 'json'
        require 'vault'
        require 'socket'
        @config = Config[:vault]
        @config[:mounts] ||= {}
        @config[:mounts][:generic] ||= ['secret']
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

        begin
          
          # Unless [:fqdn_expand] is set to 'false' we use the host name as it
          # is. If it is set to 'true' we expand the name. This is used to 
          # address correct Vault server from the cluster based on the DNS
          # information. Might not be needed for all users, so if there is 
          # no setting given nothing will happen. 
          fqdn_expand = @config[:fqdn_expand] unless @config[:addr].nil?
          if fqdn_expand
            short_hostname = @config[:addr] unless @config[:addr].nil?
            Hiera.debug("[hiera-vault] Expandin hostname #{short_hostname} to FQDN")
            vault_hostname = Socket.gethostbyname(short_hostname).first 
          else
            vault_hostname = @config[:addr] unless @config[:addr].nil?
          end
          Hiera.debug("[hiera-vault] Vault hostname: #{vault_hostname}")

          # We can have "expternal" authentication type:
          # anything or absend -> default. Host and token are hardcoded 
          # into the hiera.yaml
          # "external" -> some external program returns access token string
          # if no setting given, assume that authentication token is
          # hardcoded in the hiera.yaml
          auth_type = @config[:auth_type] unless @config[:auth_type].nil?
          if auth_type == 'external'
            Hiera.debug("[hiera-vault] Using external authentication")
            token_cmd = @config[:cmd] unless @config[:cmd].nil?
            token_cmd = token_cmd + " " + vault_hostname
            if @config[:args]
              token_cmd = token_cmd + " " + @config[:args]
            end
            Hiera.debug("[hiera-vault] Command: #{token_cmd}")
            token_result = RunCmd::cmd(token_cmd)
          else
            Hiera.debug("[hiera-vault] Using hardcoded authentication")
            token_result = @config[:token] unless @config[:token].nil?
          end
          port = @config[:port] unless @config[:port].nil?
          @vault = Vault::Client.new
          @vault.configure do |config|

            # If we have "proto" in the config then we have new styled config
            # in the other case just use the hostname + proto + port as is
            # from the config. "Proto" is defining 443 in case of the https
            # so it's more importnant then the "port".
            proto = @config[:proto] unless @config[:proto].nil?
            if proto
              config.address = proto+vault_hostname+":"+port.to_s
            else
              config.address = vault_hostname
            end
            Hiera.debug("[hiera-vault] Will connect to: #{config.address}")
            config.token = token_result
            config.ssl_pem_file = @config[:ssl_pem_file] unless @config[:ssl_pem_file].nil?
            config.ssl_verify = @config[:ssl_verify] unless @config[:ssl_verify].nil?
            config.ssl_ca_cert = @config[:ssl_ca_cert] if config.respond_to? :ssl_ca_cert
            config.ssl_ca_path = @config[:ssl_ca_path] if config.respond_to? :ssl_ca_path
            config.ssl_ciphers = @config[:ssl_ciphers] if config.respond_to? :ssl_ciphers
          end

          fail if @vault.sys.seal_status.sealed?
          Hiera.debug("[hiera-vault] Client configured to connect to #{@vault.address}")
        rescue Exception => e
          @vault = nil
          Hiera.warn("[hiera-vault] Vault configuration failed. Configuration error: #{e}")
        end
      end

      def lookup(key, scope, order_override, resolution_type)
        # Here comes 1st actual attempt to authenticate against vault
        # Ensuring we are doing this only once
        if !@initialized
          initialize_vault()
          @initialized = true
        end
        return nil if @vault.nil?

        Hiera.debug("[hiera-vault] Looking up #{key} in vault backend")

        answer = nil
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

        return answer
      end

      def lookup_generic(key, scope)
          begin
            secret = @vault.logical.read(key)
          rescue Vault::HTTPConnectionError
            Hiera.debug("[hiera-vault] Could not connect to read secret: #{key}")
          rescue Vault::HTTPError => e
            Hiera.warn("[hiera-vault] Could not read secret #{key}: #{e.errors.join("\n").rstrip}")
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
              rescue JSON::ParserError => e
                Hiera.debug("[hiera-vault] Could not parse string as json: #{e}")
              end
            end
          else
            # Turn secret's hash keys into strings
            data = secret.data.inject({}) { |h, (k, v)| h[k.to_s] = v; h }
          end
          #Hiera.debug("[hiera-vault] Data: #{data}:#{data.class}")

          return Backend.parse_answer(data, scope)
        end

      end
    end
  end
  
  