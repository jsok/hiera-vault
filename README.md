[![Gem Version Badge](https://img.shields.io/gem/v/hiera-vault.svg)](https://rubygems.org/gems/hiera-vault)
[![Build Status](https://travis-ci.org/jsok/hiera-vault.svg?branch=master)](https://travis-ci.org/jsok/hiera-vault)

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

### Hash - default

Since vault stores data in Key/Value pairs, this naturally lends itself to
returning a Hash on lookup.
For example:

    vault write secret/foo value=bar other=baz

The hiera lookup for `foo` will return a Hash:

    {"value"=>"bar","other"=>"baz"}

### Single Value - optional

If you use just a single field to store data, eg. "value" - you can request that just this is returned as a string, instead of a hash.

To do this, set:

    :vault:
        :default_field: value

For example:

    vault write secret/foo value=bar other=baz

The hiera lookup for `foo` will return just "bar" as a string.

In case `foo` does not have the `value` field, a Hash is returned as normal.
In versions <= 0.1.4 an error occurred.

#### Default field behavior - optional
When using `:default_field`, by default, additional fields are ignored, and
if the field is not present, nil will be returned.

To only return the value of the default field if it is present and the only one, set:

    :vault:
        :default_field: value
        :default_field_behavior: only

Then, when `foo` contains more fields in addition to `value`, a Hash will be returned, just like with the default behaviour.
And, in case `foo` does not contain the `value` field, a Hash with the actual fields will be returned, as if `:default_field`
was not specified.

#### JSON parsing of single values - optional
Only applicable when `:default_field` is used.
To use JSON parsing, set, for example:

    :vault:
        :default_field: json_value
        :default_field_parse: json

Then, for example, when:

    vault write secret/foo json_value='["bird","spider","fly"]'

the hiera lookup for `foo` will return an array.
When used in Array lookups (hiera_array), all occurences of `foo` will be merged into a single array.

When, for example:

    vault write secret/foo json_value='{"user1":"pass1","user2":"pass2"}'

the hiera lookup for `foo` will return a hash. This is the same behavior as when:

    vault write secret/foo user1='pass1' user2='pass2'

Both will result in a hash:

    {"user1"=>"pass1","user2"=>"pass2"}


In case the single field does not contain a parseable JSON string, the string will be returned as is.
When used in Hash lookups, this will result in an error as normal.


### Lookup type behavior

In case Array or Hash lookup is done, usual array or hash merging takes place based on the configured global `:merge_behavior` setting.


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


Since version 0.2.0, the `:hierarchy` source paths from the hiera configuration are used
on top of each mount.
This makes the behavior of the vault backend the same as other backends.
Additionally, this enables usage of the third parameter to the hiera functions in puppet,
the so-called 'override' parameter.
See http://docs.puppetlabs.com/hiera/1/puppet.html#hiera-lookup-functions

Example: In case we have the following hiera config:

    :backends:
        - vault
        - yaml

    :hierarchy:
      - "nodes/%{::fqdn}"
      - "hostclass/%{::hostclass}"
      - ...
      - common

    :yaml:
      :datadir: "/var/lib/hiera/%{::environment}/"

    :vault:
        :addr: ...
        :mounts:
            :generic:
                - "%{::environment}"
                - secret

Each hiera lookup will result in a lookup under each mount, honouring the configured `:hierarchy`. e.g.:

    %{::environment}/nodes/%{::fqdn}
    %{::environment}/hostclass/${::hostclass}
    %{::environment}/...
    %{environment}/common
    secret/nodes/%{::fqdn}
    secret/hostclass/%{::hostclass}
    secret/...
    secret/common

With the third argument to the hiera functions, the `override` parameter, the call

    $val = hiera('thekey', 'thedefault', 'override_path/look_here_first')

will result in lookups through the following paths in vault:

    %{::environment}/override_path/look_here_first
    %{::environment}/nodes/%{::fqdn}
    %{::environment}/hostclass/%{::hostclass}
    %{::environment}/...
    %{::environment}/common
    secret/override_path/look_here_first
    secret/nodes/%{::fqdn}
    secret/hostclass/%{::hostclass}
    secret/...
    secret/common


## SSL

SSL can be configured with the following config variables:

    :vault:
        :ssl_pem_file: /path/to/pem
        :ssl_ca_cert: /path/to/ca.crt
        :ssl_ca_path: /path/to/ca/
        :ssl_verify: false
        :ssl_ciphers: "MY:SSL:CIPHER:CONFIG"
