+++
title = "Apache: Redirect if domain name does not match"
description = "Apache RewriteRule for requests that do NOT match a domain name"
[taxonomies]
tags = ["apache"]
+++

Redirect everything to dratir.ch:

```conf
RewriteEngine On
Rewritecond %{HTTP_HOST} !^dratir\.com
RewriteRule (.*) http://dratir.com/$1 [QSA,R=301,L]
```
