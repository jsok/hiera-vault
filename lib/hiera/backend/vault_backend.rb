# Vault backend for Hiera
class Hiera
  module Backend
    class Vault_backend
      def initialize
        require 'json'
        require 'vault'

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
          @vault = Vault::Client.new
          @vault.configure do |config|
            config.address = @config[:addr] unless @config[:addr].nil?
            config.token = @config[:token] unless @config[:token].nil?
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
          Hiera.warn("[hiera-vault] Skipping backend. Configuration error: #{e}")
        end

        @cache = {}
        @config[':cache_timeout'] ||= 10
        @config[:cache_clean_interval] ||= 3600
      end

      def lookup(key, scope, order_override, resolution_type)
        return nil if @vault.nil?

        Hiera.debug("[hiera-vault] Looking up #{key} in vault backend") 

        answer = nil
        found = false

        # Only generic mounts supported so far
        @config[:mounts][:generic].each do |mount|
          path = Backend.parse_string(mount, scope, { 'key' => key })
          Backend.datasources(scope, order_override) do |source|
            Hiera.debug("[hiera-vault] Looking in path #{path}/#{source}/")
            data = lookup_generic_with_cache("#{path}/#{source}/#{key}")
            #Hiera.debug("[hiera-vault] Answer: #{new_answer}:#{new_answer.class}")
            next if data.nil?
            found = true
            new_answer = Backend.parse_answer(data, scope)

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
              break
            end
          end
        end

        return answer
      end

      private

      def lookup_generic_with_cache(key)
        return lookup_generic(key) if @config[:cache_timeout] <= 0

        now = Time.now.to_i
        expired_at = now + @config[:cache_timeout]

        periodically_clean_cache(now) unless @config[:cache_clean_interval] == 0

        if !@cache[key] || @cache[key][:expired_at] < now
          Hiera.debug("[hiera-vault] Lookup #{key} in vault")
          @cache[key] = {
            :expired_at => expired_at,
            :result => lookup_generic(key)
          }
        else
          Hiera.debug("[hiera-vault] #{key} found in cache")
        end
        return @cache[key][:result]
      end

      def lookup_generic(key)
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
          data = secret.data.inject({}) { |h, (k, v)| h[k.to_s] = v; h }
        end
        #Hiera.debug("[hiera-vault] Data: #{data}:#{data.class}")

        return data
      end

      def periodically_clean_cache(now)
        return if now < @clean_cache_at.to_i
        
        @clean_cache_at = now + @config[:cache_clean_interval]
        @cache.delete_if do |_, entry|
          entry[:expired_at] < now
        end 
      end

    end
  end
end
