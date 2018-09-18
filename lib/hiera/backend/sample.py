#!/usr/bin/env python
'''
Sample authentication script for Kerberos authentication
of the FreeIPA enrolled host against Vault server.

Arguments: 
            hostname  - Vault server URL (without protocol)
            auth_type - host or user

Returns authentication token (usually valid for 30 minutes).
'''

import argparse
import kerberos
import requests


parser = argparse.ArgumentParser()
parser.add_argument('url', help='Vault server URL (without protocol)')
parser.add_argument('type', choices=('host', 'user'))
args = parser.parse_args()

service = 'HTTP@%s' % args.url
mechanism = kerberos.GSS_MECH_OID_SPNEGO
_, ctx = kerberos.authGSSClientInit(service, mech_oid=mechanism)

kerberos.authGSSClientStep(ctx, '')
kerberos_token = kerberos.authGSSClientResponse(ctx)

url = 'https://%s/v1/auth/%ss/login' % (args.url, args.type)
data = {'authorization': 'Negotiate %s' % kerberos_token}
r = requests.post(url, json=data, verify='/etc/ipa/ca.crt')
if r.ok:
    print r.json()['auth']['client_token']
else:
    raise Exception('Error authenticating: %s' % r.json())
