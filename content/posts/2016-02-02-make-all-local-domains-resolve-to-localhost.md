+++
title = "Make all *.local domains resolve to localhost"
description = "Use dnsmasq to resolve a wildcard domain on Linux"
[taxonomies]
tags = ["dns", "linux"]
+++

It's time for my yearly blog post, so let's get started!

Some development environments use `*.local`-domains which point to localhost. Creating a hosts-entry for every single domain is not an elegant solution, so let's do something easier: let's use dnsmasq to resolve ALL .local-domains to localhost!

_Tested on CentOS 7, but should work similarly for other Linuxes._

All commands assume you have root privileges. If you are not logged in as `root`, prepend `sudo` to all commands.

First, make sure **dnsmasq** is installed:

```
yum install dnsmasq
```

Ok, now we have to tell dnsmasq to listen for queries. Add the following line to `/etc/dnsmasq.conf`:

```
listen-address=127.0.0.1
```

Next, create a "zone file" for `.local`. Create a file `/etc/dnsmasq.d/local` and add the following:

```
address=/local/127.0.0.1
```

This tells dnsmasq to resolve queries to `*.local` to `127.0.0.1`.

Now, start up dnsmasq. Also enable "autostart":

```
systemctl restart dnsmasq
systemctl enable dnsmasq
```

Ok, now that we set up a local DNS server, let's tell our DHCP client to actually use it. Add the following line to `/etc/dhcp/dhclient.conf`:

```
prepend domain-name-servers=127.0.0.1;
```

Last step: let the DHCP client apply the new settings:

```
dhclient
```

And that's it! Let's make a quick test:

```
$ ping foo.local
PING foo.local (127.0.0.1) 56(84) bytes of data.
64 bytes from localhost (127.0.0.1): icmp_seq=1 ttl=64 time=0.017 ms
64 bytes from localhost (127.0.0.1): icmp_seq=2 ttl=64 time=0.068 ms
# ...
```

Success!
