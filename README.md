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
[vault-ruby](https://github.com/hashicorp/vault-ruby), e.g.

    VAULT_TOKEN=secret hiera -c hiera.yml secret/foo


## Lookups

Since vault stores data in Key/Value pairs, this naturally lends itself to returning a Hash on lookup.
For example:

    vault write secret/foo value=bar other=baz

Will return in a hiera lookup:

    {"value"=>"bar","other"=>"baz"}


## TODO

This is very much alpha, some improvements:

 - [ ] Add configuration options for SSL/TLS
 - [ ] Setup CI
 - [ ] Upload to Puppet Forge
