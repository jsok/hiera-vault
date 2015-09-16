[![Gem Version Badge](https://img.shields.io/gem/v/hiera-vault.svg)](https://rubygems.org/gems/hiera-vault)

# hiera-vault
A Hiera backend to retrieve secrets from Hashicorp's Vault

[Vault](https://vaultproject.io) secures, stores, and tightly controls access to tokens, passwords, certificates, API keys, and other secrets in modern computing. Vault handles leasing, key revocation, key rolling, and auditing. Vault presents a unified API to access multiple backends: HSMs, AWS IAM, SQL databases, raw key/value, and more.

## Configuration

You should modify `hiera.yaml` as follows:

    :backends:
        - vault

    :vault:
        :addr: http://127.0.0.1:8200
        :token: fake

Alternatively (and recommended) you can specify your vault client configuration
via the same environment variables read by
[vault-ruby](https://github.com/hashicorp/vault-ruby#usage), e.g.

    VAULT_TOKEN=secret hiera -c hiera.yml foo


## Lookups

Since vault stores data in Key/Value pairs, this naturally lends itself to
returning a Hash on lookup.
For example:

    vault write secret/foo value=bar other=baz

The hiera lookup for `foo` will return a Hash:

    {"value"=>"bar","other"=>"baz"}

## Backends and Mounts

The `mounts` config attribute should be used to customise which secret backends
are interrogated in a hiera lookup.

Currently only the `generic` secret backend is supported.
By default the `secret/` mount is used if no mounts are specified.

Inspect your `vault mounts` output, e.g.:

    > vault mounts
    Path        Type     Description
    staging/    generic  generic secret storage for Staging data
    production/ generic  generic secret storage for Production data
    secret/     generic  generic secret storage
    sys/        system   system endpoints used for control, policy and debugging

For the above scenario, you may wish to separate your per-environment secrets
into their own mount. This could be achieved with a configuration like:

    :vault:
        # ...
        :mounts:
            :generic:
                - %{environment}
                - secret

## Default field

Vault has the ability to store many fields inside an object. By default, we return all of them as a hash.

If you just use a single field to store data, eg. 'value' - you can request that just this is returned as a string, instead of a hash.

To do this, set:

    :vault:
        :default_field: value


## SSL

SSL can be configured with the following config variables:

    :vault:
        :ssl_pem_file: /path/to/pem
        :ssl_ca_cert: /path/to/ca.crt
        :ssl_ca_path: /path/to/ca/
        :ssl_verify: false
        :ssl_ciphers: "MY:SSL:CIPHER:CONFIG"

## TODO

This is very much alpha, some improvements:

 - [ ] Setup CI
 - [ ] Upload to Puppet Forge
