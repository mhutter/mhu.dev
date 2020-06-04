---
date: 2016-02-02T13:37:00+01:00
title: Make all *.dev domains resolve to localhost
summary: Use dnsmasq to resolve a wildcard domain on Linux
tags: [dnsmasq,dns,centos]
---

It's time for my yearly blog post, so let's get started!


**Update 2018/07/13** _Both Chrome and Firefox now [enforces HTTPS on all `.dev` (and `.foo`) domains via a preloaded HSTS header](https://ma.ttias.be/chrome-force-dev-domains-https-via-preloaded-hsts/). This means that you have to use something else for your development environment. Or even better, make sure your app does native HTTPS! If you think "my app doesn't need HTTPS, I don't handle any information" you should read [Troy Hunts excellent "Here's Why Your Static Website Needs HTTPS"](https://www.troyhunt.com/heres-why-your-static-website-needs-https/)._

Some development environments use *.dev-domains which point to localhost. Creating a hosts-entry for every single domain is not an elegant solution, so let's do something easier: let's use dnsmasq to resolve ALL .dev-domains to localhost!

_Tested on CentOS 7, but should work similarly for other Linuxes._

All commands assume you have root privileges. If you are not logged in as `root`, prepend `sudo` to all commands.

First, make sure **dnsmasq** is installed:

    yum install dnsmasq

Ok, now we have to tell dnsmasq to listen for queries. Add the following line to `/etc/dnsmasq.conf`:

    listen-address=127.0.0.1

Next, create a "zone file" for `.dev`. Create a file `/etc/dnsmasq.d/dev` and add the following:

    address=/dev/127.0.0.1

This tells dnsmasq to resolve queries to `*.dev` to `127.0.0.1`.

Now, start up dnsmasq. Also enable "autostart":

    systemctl restart dnsmasq
    systemctl enable dnsmasq

Ok, now that we set up a local DNS server, let's tell our DHCP client to actually use it. Add the following line to `/etc/dhcp/dhclient.conf`:

    prepend domain-name-servers=127.0.0.1;

Last step: let the DHCP client apply the new settings:

    dhclient

And that's it! Let's make a quick test:

    $ grep -i dev /etc/hosts
    $ ping foo.dev
    PING foo.dev (127.0.0.1) 56(84) bytes of data.
    64 bytes from localhost (127.0.0.1): icmp_seq=1 ttl=64 time=0.017 ms
    64 bytes from localhost (127.0.0.1): icmp_seq=2 ttl=64 time=0.068 ms
    # ...

Success!
