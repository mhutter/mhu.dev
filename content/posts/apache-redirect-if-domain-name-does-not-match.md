---
date: 2011-12-14T13:37:00+01:00
title: "Apache: Redirect if domain name does not match"
summary: Apache RewriteRule for requests that do NOT match a domain name
tags: [apache]
---
Redirect everything to dratir.ch:

```apache
RewriteEngine On
Rewritecond %{HTTP_HOST} !^dratir\.com
RewriteRule (.*) http://dratir.com/$1 [QSA,R=301,L]
```
