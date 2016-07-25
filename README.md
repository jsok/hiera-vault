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


## Flagged usage - optional
By default all hiera lookups are done through all backends.
In case of vault, it might be desirable to skip vault in normal
hiera lookups, while you already know up front that the key is not present
in vault.
Lookups in vault are relatively expensive, since for each key a connection to vault
is made as many times as there are mounts and even a multiple of that when using the
`:hierarchy` list.
Additionally it might also be desirable to lookup keys in vault only.

To accomplish this, the vault backend can be configured with the following:

    :vault:
        :override_behavior: 'flag'
        :flag_default: 'vault_only'

To make this work, this gem comes with three specific functions named `hiera_vault`,
`hiera_vault_array`, and `hiera_vault_hash`, which should be used instead of the
corresponding normal hiera lookup functions, to get data out of vault.
Without the `:flag_default` option, or when set to 'vault_first', lookups will be done in vault first, and then in
the other backends. If `:flag_default` is set to 'vault_only', the `hiera_vault*` functions
will only use the vault backend.
With `:override_behavior` set to 'flag', the vault backend will skip looking in vault when
lookups are done with the normal hiera lookup functions.

When using any of the specific functions, a puppet run will fail with an error stating:

    [hiera-vault] Cannot skip, because vault is unavailable and vault must be read, while override_behavior is 'flag'


### Auto-generating and writing secrets with `hiera_vault()` - `:default_field` required
This works only when `:default_field` has been configured and `:override_behavior: 'flag'` is in
effect.

When using the following call with `hiera_vault` in your puppet code, a password will be generated
automatically and stored at the `override` or highest level hierarchy path, in case no `override`
has been specified:

    $some_password = hiera_vault('some_key', {'generate' => 20}, 'some_override_path')

In case the `key` does not exist at any path in the mounts/hierarchy lists, a password string will
be generated with the given length, using alphanumeric characters only. Then it will be stored in
vault at the first path that was examined. As such it is highly recommended to use an override path
to ensure using the same value on different nodes, in case that's desired.
In some cases it might be desired to have a different password on each node. In such a case,
`$::fqdn` can be used as the override parameter.


## SSL

SSL can be configured with the following config variables:

    :vault:
        :ssl_pem_file: /path/to/pem
        :ssl_ca_cert: /path/to/ca.crt
        :ssl_ca_path: /path/to/ca/
        :ssl_verify: false
        :ssl_ciphers: "MY:SSL:CIPHER:CONFIG"
