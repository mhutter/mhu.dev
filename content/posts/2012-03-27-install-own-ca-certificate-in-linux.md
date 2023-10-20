+++
title = "Install own CA-Certificate in Linux"
description = "How to install your own CA certificate"
aliases = ["posts/install-own-ca-certificate-in-linux"]
[taxonomies]
tags = ["linux"]
+++

**Overview**

- [Ubuntu, SLES, Debian](#ubuntu-sles-debian)
- [CentOS, RHEL](#centos)

## Ubuntu, SLES, Debian

_Tested under **Ubuntu** and **SLES 11** so far._

### Required Packages

install with `apt-get install ...` or similar

* `openssl`

### Steps

```sh
# Step 0: Convert the Certificate to PEM format
openssl x509 -inform der -in certificate.cer -out certificate.pem

# Step 0.5: Make sure there is only 1 Certificate in the File
grep 'BEGIN.* CERTIFICATE' certificate.pem | wc -l # should output `1`

# Step 1: Verify it's the correct Certificate
openssl x509 -noout -fingerprint -in certificate.pem

# Step 2: Copy the File to /etc/ssl/certs
# Do I really have to explain that? If you can't do that on your own you
# probably shouldn't be installing CA-Certificates anyway...

# Step 3: Find out the Hash of your Cert
openssl x509 -noout -hash -in certificate.pem

# Step 4: Inside /etc/ssl/certs, link your certificate to "hash.0"
ln -s certificate.pem `openssl x509 -hash -noout -in certificate.pem`.0
```


## CentOS

### Required Packages

install with `yum install ...` or similar

* `ca-certificates`

### Steps

```sh
# Enable the CA configuration feature
update-ca-trust enable

# Add the new certificate to `/etc/pki/ca-trust/source/anchors`
cp certificate.cer /etc/pki/ca-trust/source/anchors/

# update the CA certs
update-ca-trust extract
```

And that's it!
