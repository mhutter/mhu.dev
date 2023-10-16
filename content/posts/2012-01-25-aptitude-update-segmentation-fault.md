+++
title = "aptitude update gives Segmentation Fault"
description = "TL;DR: `rm /var/cache/apt/*.bin`"
[taxonomies]
tags = ["linux"]
+++

In case I forget again…

Problem on Ubuntu 10.04 (Lucid Lynx) x64:

    $ sudo aptitude update
    Hit http://security.ubuntu.com lucid-security Release.gpg
    Ign http://security.ubuntu.com/ubuntu/ lucid-security/main Translation-en_US
    Ign http://security.ubuntu.com/ubuntu/ lucid-security/restricted Translation-en_US
    ...
    Hit http://us.archive.ubuntu.com lucid-updates/multiverse Sources
    Reading package lists... Done
    Segmentation fault

Solution:

    sudo rm /var/cache/apt/*.bin
    sudo apt-get update

Aptitude should now work again.
