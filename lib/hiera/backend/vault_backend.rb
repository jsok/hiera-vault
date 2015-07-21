# Vault backend for Hiera
class Hiera
  module Backend
    class Vault_backend

      def initialize()
        require 'json'
        require 'vault'

        @config = Config[:vault]
        @config[:mounts] ||= {}
        @config[:mounts][:generic] ||= ['secret']

        begin
          @vault = Vault::Client.new(address: @config[:addr], token: @config[:token])
          @vault.ssl_verify = false if @config[:ssl_no_verify] == true
          fail if @vault.sys.seal_status.sealed?
          Hiera.debug("[hiera-vault] Client configured to connect to #{@vault.address}")
        rescue Exception => e
          @vault = nil
          Hiera.warn("[hiera-vault] Skipping backend. Configuration error: #{e}")
        end
      end

      def lookup(key, scope, order_override, resolution_type)
        return nil if @vault.nil?

        Hiera.debug("[hiera-vault] Looking up #{key} in vault backend")

        answer = nil

        # Only generic mounts supported so far
        @config[:mounts][:generic].each do |mount|
          path = Backend.parse_string(mount, scope, { 'key' => key })
          answer = lookup_generic("#{path}/#{key}", scope)

          break if answer.kind_of? Hash
        end

        answer
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
          # Turn secret's hash keys into strings
          data = secret.data.inject({}) { |h, (k, v)| h[k.to_s] = v; h }

          return Backend.parse_answer(data, scope)
      end

    end
  end
end
