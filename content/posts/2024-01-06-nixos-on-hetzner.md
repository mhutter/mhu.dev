+++
title = "NixOS on Hetzner Dedicated"
[taxonomies]
tags = ["nixos", "hetzner"]
+++

As it is currently fashionable for the Nerd interested in all things Nix(OS), I have set up my own NixOS Server on Hetzner Dedicated. I'll first go over the setup details, and then describe how I set everything up. Unfortunately, Documentation around the Nix ecosystem is pretty "meh" (being used the high quality of documentation in the Rust ecosystem), so maybe this helps someone else along the way.

<!-- more -->

The purpose of this server is a home for some tools I host for myself, that are currently deployed on various Kubernetes clusters. While I love Kubernetes and what it does for scalability and resilience, the added complexity is rarely worth the trouble for simple setups that don't need endless scalability, zero-downtime-deployments, and high availability.

I already used Nix (with Home Manager) to manage many aspects of my workstation, so I was confident I could get _somewhere_.

## Overview

On the Hetzner Server Auctions, I got my hands on a Server with the following specs:

* AMD Ryzen 9 3900 (s2 cores/24 threads)
* 128 GB DDR 4 ECC RAM
* 2 x 1.92 TB NVMe Datacenter SSDs

It comes with a 1 Gigabit NIC, both IPv4 and IPv6 addresses, and unlimited traffic.

This should bring me quite far in terms of resources. And if I ever reach capacity, it should be trivial to add another server (using this post as a reference!).

## The desired state

In the end, the setup should look like this:

### RAID1 for the disks

This is for fault tolerance.

### Full disk encryption (except `/boot`)

The server will host personal information, so I want everything to be encrypted at rest.

I'll be using plain old `ext4` on LUKS. Why not ZFS, you might ask? Simple: I know LUKS and ext4, but I don't know ZFS.

Since I don't want to store the encryption password on the (unencrypted) boot partition, and the server does not have a TPM module, this means making sure I can SSH into the boot loader to unlock the crypt volume.

[Early boot remote decryption on NixOS](https://mth.st/blog/nixos-initrd-ssh/) was a tremendous help in getting this part set up!

Further reading:
- [Remote LUKS Unlocking](https://nixos.wiki/wiki/Remote_LUKS_Unlocking)

### Ephemeral root file system

A thought I have played with for a long time. Since there will be a lot of tinkering going on on this server, it's especially valuable to avoid cruft.
The general idea is that on `/` you mount a `tmpfs` or similar, and on `/nix` you mount your actual persistent storage.
NixOS will then take care of linking/copying the whole operating system on boot.
For folders that need to be persisted (e.g. `/var/lib/somedb`), you bind-mount them to a directory on `/nix/persist`.

See the following excellent articles for more details, but I'll also outline the setup below.
- [NixOS ❄: tmpfs as root](https://elis.nu/blog/2020/05/nixos-tmpfs-as-root/)
- [Erase your darlings](https://grahamc.com/blog/erase-your-darlings)

## Initial development

For initial experimentation, I booted a local Qemu VM. I was especially interested in testing the aspects of the NVMe disks.

To start the VM, I used the following command:

```sh
# Prepare the disk images
fallocate -l 80G nvm0.img
fallocate -l 80G nvm1.img

# Boot VM
qemu-system-x86_64 \
  -drive file=$(readlink -f ./nixos-minimal-23.11.iso),format=raw \
  -drive file=nvm0.img,if=none,id=nvm0,format=raw,format=raw \
  -drive file=nvm1.img,if=none,id=nvm1,format=raw,format=raw \
  -device nvme,serial=deadbeef,drive=nvm0 \
  -device nvme,serial=cafebabe,drive=nvm1 \
  -device e1000,netdev=net0 -netdev user,id=net0,hostfwd=tcp:127.0.0.1:5555-:22 \
  -m 8G \
  -enable-kvm
```

This command will
- mount the NixOS ISO image
- attach the two image files as NVMe devices
- attach a NIC and forward port 5555 from the host to port 22 on the guest

I then started writing a `setup.sh` script that does all the partitioning and installation.

In a separate terminal, I ran [`entr`](https://eradman.com/entrproject/) to upload the script every time I edited it:

```sh
ls -1 setup.sh | entr scp ./setup.sh root@127.0.0.1:5555:setup.sh
```

This allowed me to quickly iterate on the script.

I however quickly got bored, and I also realized that the Hetzner Rescue system will have a different toolset installed than the NixOS ISO I was using.

## Setup

So I proceeded to work on the REAL server. Once it was provisioned, I first changed the Firewall rules in the Robot WebGUI to only allow SSH access from my IP. I used the following incoming rules:

| Name | Version | Protocol | Source IP | Dest. IP | Source Port | Dest. Port | TCP Flags | Action |
| ---- | ---- | ---- | ---- | ---- | ---- | ---- | ---- | ---- |
| ICMP | ipv4 | icmp |  |  |  |  |  | accept |
| SSH | ipv4 | tcp | 1.2.3.4/32 |  |  | 22 |  | accept |
| TCP | ipv4 | tcp |  |  |  |  | ack\|rst | accept |
| DNS | ipv4 | * |  |  |  | 53 |  | accept |

And for outgoing just an "Allow all" rule.

I then booted the machine into the Linux rescue system, and started `entr` again, continuing work on my `setup.sh`. I got (= copied over) most of the steps from the following sources:

- [serokell's `nixos-install-scripts`](https://github.com/serokell/nixos-install-scripts/blob/fbbda90fda62b22b3ebc0dd0a417a9413786f26f/hosters/hetzner-dedicated/hetzner-dedicated-wipe-and-install-nixos.sh)
- [Paranoid NixOS Setup](https://xeiaso.net/blog/paranoid-nixos-2021-07-18/)

In the end, the whole setup script looked something like this:

```sh
#!/usr/bin/env bash
set -e -u -o pipefail -x

lsblk

# Undo any previous changes.
# This allows me to re-run the script many times over
set +e
umount -R /mnt
cryptsetup close cryptroot
vgchange -an
set -e

# Prevent mdadm from auto-assembling any preexisting arrays.
# Otherwise mdadm might detect existing raid signatures after
# partitioning, and start reassembling the array.
mdadm --stop --scan
echo 'AUTO -all
ARRAY <ignore> UUID=00000000:00000000:00000000:00000000' > /etc/mdadm/mdadm.conf

# Partitioning
for disk in /dev/nvme?n1; do
  # This is a BIOS system, so let's avoid GPT
  # Also we only have 2 partitions, so ...
  parted --script --align=optimal "$disk" -- mklabel msdos
  # The boot partition(s)
  parted --script --align=optimal "$disk" -- mkpart primary ext4 1M 1G
  parted --script --align=optimal "$disk" -- set 1 boot on
  # The rest
  parted --script --align=optimal "$disk" -- mkpart primary ext4 1GB '100%'
done

# Reload partition tables.
partprobe || :
# Wait for all partitions to show up
udevadm settle --timeout=5s --exit-if-exists=/dev/nvme0n1p1
udevadm settle --timeout=5s --exit-if-exists=/dev/nvme0n1p2
udevadm settle --timeout=5s --exit-if-exists=/dev/nvme1n1p1
udevadm settle --timeout=5s --exit-if-exists=/dev/nvme1n1p2

# Wipe any previous RAID signatures
mdadm --zero-superblock --force /dev/nvme0n1p2
mdadm --zero-superblock --force /dev/nvme1n1p2

# Create the RAID array
# This is the first hairy bit.
# - make sure "name" matches the device name
# - make sure "homehost" matches what your hostname will be after setup
mdadm --create --run --verbose \
  /dev/md0 \
  --name=md0 \
  --level=raid1 --raid-devices=2 \
  --homehost=myhostname  \
  /dev/nvme0n1p2 \
  /dev/nvme1n1p2

# Remove traces from preexisting filesystems etc.
vgchange -an
wipefs -a /dev/md0

# Disable RAID recovery for now
echo 0 > /proc/sys/dev/raid/speed_limit_max

# Set up encryption
# At this point, the script will ask for the LUKS passphrase _twice_
cryptsetup -q -v luksFormat /dev/md0
cryptsetup -q -v open /dev/md0 cryptroot

# Create filesystems
# We'll make heavy use of labels to identify the FS' later
mkfs.ext4 -F -L boot0 /dev/nvme0n1p1
mkfs.ext4 -F -L boot1 /dev/nvme1n1p1
mkfs.ext4 -F -L nix -m 0 /dev/mapper/cryptroot

# Refresh disk/by-uuid entries
udevadm trigger
udevadm settle --timeout=5 --exit-if-exists=/dev/disk/by-label/nix

# Mount filesystems
mount -t tmpfs none /mnt

# Create & mount additional mount points
mkdir -pv /mnt/{boot,boot-fallback,nix,etc/{nixos,ssh},var/{lib,log},srv}

mount /dev/disk/by-label/boot0 /mnt/boot
mount /dev/disk/by-label/boot1 /mnt/boot-fallback
mount /dev/disk/by-label/nix   /mnt/nix

# Create & mount directories for persistence
mkdir -pv /mnt/nix/{secret/initrd,persist/{etc/{nixos,ssh},var/{lib,log},srv}}
chmod 0700 /mnt/nix/secret

mount -o bind /mnt/nix/persist/etc/nixos /mnt/etc/nixos
mount -o bind /mnt/nix/persist/var/log   /mnt/var/log

# Install Nix
apt-get update
apt-get install -y sudo
mkdir -p /etc/nix
echo "build-users-group =" >> /etc/nix/nix.conf
curl -sSL https://nixos.org/nix/install | sh
set +u +x # sourcing this may refer to unset variables that we have no control over
. "$HOME/.nix-profile/etc/profile.d/nix.sh"
set -u -x

nix-channel --add https://nixos.org/channels/nixos-unstable nixpkgs
nix-channel --update

# Getting NixOS installation tools
nix-env -iE "_: with import <nixpkgs/nixos> { configuration = {}; }; with config.system.build; [ nixos-generate-config nixos-install nixos-enter ]"

# Generated initrd SSH host key
ssh-keygen -t ed25519 -N "" -C "" -f /mnt/nix/secret/initrd/ssh_host_ed25519_key
```

The last bit is important since we need to SSH into our boot loader to unlock the cryptvolume, and since this host key will be stored on an unencrypted volume, we want to have a different one from our main host key. We also don't want to have it in our NixOS config, since then it would end up in the world-readable `/nix/store`.

Once the script is completed, we're left with a partitioned system and Nix installed, ready to set up NixOS.

On a side note, the sourced Nix profile is not exported outside the script, so after the script completes you either have to log in again, or run:

```sh
. "$HOME/.nix-profile/etc/profile.d/nix.sh"
```

Now you can use `nix`, `nixos-generate-config`, `nixos-install` etc!

## Bootstrap NixOS configuration

The next step is to prepare a NixOS configuration that is just enough to bootstrap NixOS and boot into.

This mostly means we need the following

- Ensure everything is mounted correctly
- Network configuration for the Bootloader and "main" operating system (there is no DHCP)
- We can SSH into the initrd and unlock the cryptvolume
- We can SSH into the fully booted server

Everything else will be configured later.

To prepare the NixOS configuration, I generated a template using `nixos-generate-config --root /mnt`, downloaded the files, edited them locally, and pushed them to my server using `entr` again:

```sh
ls -1 *.nix | entr scp *.nix root@1.2.3.4:/mnt/etc/nixos/
```

In the end, my NixOS configuration looked like this:

```nix
# configuration.nix
{ config, lib, pkgs, ... }:

{
  imports = [ ./hardware-configuration.nix ];

  boot.loader.grub = {
    enable = true;
    device = "/dev/nvme0n1";

    # We don't raid the boot parts, instead we copy everything
    # over to the second disk
    mirroredBoots = [{
      devices = [ "/dev/nvme1n1" ];
      path = "/boot-fallback";
    }];
  };

  # We need networking in the initrd
  boot.initrd.network = {
    enable = true;
    ssh = {
      enable = true;
      # Make sure this is different from your "main" SSH port,
      # otherwise you'll get conflicting SSH host keys.
      # Also save yourself some hassle and _never_ use port 22 for SSH.
      port = 1234;
	  # this is the default
      # authorizedKeys = config.users.users.root.openssh.authorizedKeys.keys;
      hostKeys = [ "/nix/secret/initrd/ssh_host_ed25519_key" ];
    };
  };

  networking.hostName = "myhostname"; # Define your hostname.

  # Ensure the initrd knows about mdadm
  boot.swraid.enable = true;
  boot.swraid.mdadmConf = ''
    HOMEHOST myhostname
  '';

  # Now this is hairy! The format is more or less:
  # IP:<ignore>:GATEWAY:NETMASK:HOSTNAME:NIC:AUTCONF?
  # See: https://www.kernel.org/doc/Documentation/filesystems/nfs/nfsroot.txt
  boot.kernelParams = [ "ip=1.2.3.4::1.2.3.1:255.255.255.192:myhostname:enp35s0:off" ];
  networking = {
    useDHCP = false;
    interfaces."enp35s0" = {
      ipv4.addresses = [{ address = "1.2.3.4"; prefixLength = 26; }];
      ipv6.addresses = [{ address = "2a01:xx:xx::1"; prefixLength = 64; }];
    };
    defaultGateway = "1.2.3.1";
    defaultGateway6 = { address = "fe80::1"; interface = "enp35s0"; };
  };

  time.timeZone = "UTC";

  users.mutableUsers = false;
  # Since I'm the only one SSHing into this server, I won't bother
  # setting up additional users.
  users.users.root = {
    openssh.authorizedKeys.keys = [ "ssh-ed25519 AAAAyourpublickeyobviously" ];
  };

  environment.systemPackages = with pkgs; [ vim wget ];

  services.openssh = {
    enable = true;
    # Again, don't use 22.
    ports = [ 5678 ];
    settings.PermitRootLogin = "prohibit-password";
  };

  # Open ports in the firewall.
  # turned out that services.openssh does this by default :)
  networking.firewall.allowedTCPPorts = [ ] ++ config.services.openssh.ports;
  system.stateVersion = "24.05"; # Did you read the comment?

  # Persist individual files that are not covered by bind mounts
  environment.etc."ssh/ssh_host_rsa_key".source = "/nix/persist/etc/ssh/ssh_host_rsa_key";
  environment.etc."ssh/ssh_host_rsa_key.pub".source = "/nix/persist/etc/ssh/ssh_host_rsa_key.pub";
  environment.etc."ssh/ssh_host_ed25519_key".source = "/nix/persist/etc/ssh/ssh_host_ed25519_key";
  environment.etc."ssh/ssh_host_ed25519_key.pub".source = "/nix/persist/etc/ssh/ssh_host_ed25519_key.pub";
  environment.etc."machine-id".source = "/nix/persist/etc/machine-id";
}
```

Most of the network-related information (IP, Gateways, Subnet masks/prefix length) you can get from the Hetzner Robot WebGUI. To get the NIC name (it's NOT `eth0` as in the rescue system), I used the following snippet from Serokell's setup script:

```sh
RESCUE_INTERFACE=$(ip route get 8.8.8.8 | grep -Po '(?<=dev )(\S+)')
INTERFACE_DEVICE_PATH=$(udevadm info -e | grep -Po "(?<=^P: )(.*${RESCUE_INTERFACE})")
UDEVADM_PROPERTIES_FOR_INTERFACE=$(udevadm info --query=property "--path=$INTERFACE_DEVICE_PATH")
NIXOS_INTERFACE=$(echo "$UDEVADM_PROPERTIES_FOR_INTERFACE" | grep -o -E 'ID_NET_NAME_PATH=\w+' | cut -d= -f2)
echo "Determined NIXOS_INTERFACE as '$NIXOS_INTERFACE'"
```

The hardware config I only adjusted minimally:

```nix
# hardware-configuration.nix
{ config, lib, pkgs, modulesPath, ... }:

{
  imports =
    [
      (modulesPath + "/installer/scan/not-detected.nix")
    ];

  # We need some extra stuff available in the initrd:
  # - nvme for, well, NVMe drives
  # - igb the NIC driver (see below)
  # - aesni_intel and cryptd for LUKS
  boot.initrd.availableKernelModules = [
    "aesni_intel"
    "ahci"
    "cryptd"
    "igb"
    "nvme"
  ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ "kvm-amd" ];
  boot.extraModulePackages = [ ];

  fileSystems."/" = {
    device = "none";
    fsType = "tmpfs";
    # Here I added the `size=2G` to limit memory usage.
    options = [ "defaults" "size=2G" "mode=0755" ];
  };

  # All other filesystems I changed to use `by-label`
  fileSystems."/boot" = {
    device = "/dev/disk/by-label/boot0";
    fsType = "ext4";
  };
  fileSystems."/boot-fallback" = {
    device = "/dev/disk/by-label/boot1";
    fsType = "ext4";
  };
  fileSystems."/nix" = {
    device = "/dev/disk/by-label/nix";
    fsType = "ext4";
  };

  # This must match our "name" from the mdadm setup
  boot.initrd.luks.devices."cryptroot".device = "/dev/md0";

  # Bind mounts should have been autodetected
  fileSystems."/etc/nixos" = {
    device = "/nix/persist/etc/nixos";
    fsType = "none";
    options = [ "bind" ];
  };
  fileSystems."/var/log" = {
    device = "/nix/persist/var/log";
    fsType = "none";
    options = [ "bind" ];
  };

  swapDevices = [ ];

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
}
```

To figure out which kernel module was needed for the NIC, I used the following command:

```sh
lspci -v | grep -iA20 'network\|ethernet'
```
It will list "Kernel modules" - that's what you'll need!

Once we have all of this in place, we can finally install NixOS:

```sh
nixos-install --no-root-passwd --root /mnt --max-jobs 40
```

The installer will carry away, download everything it needs to the Nix store, and configure the system as we desire.

Now all that is left to do for us, is:

```sh
# cross fingers
umount -R /mnt
reboot
```

Now note that this is a physical server, it will take some time to reboot! Use this time to adjust the Firewall rules for your server to add the new SSH ports. Otherwise, you won't be connecting to that server today ...

Use `ping IPv4_ADDR` to wait for the host to come up again, and then SSH into the initrd - I hope you wrote down the port numbers you used :-)

Once inside a shell, you can run `cryptsetup-askpass`. If everything is configured correctly, it will ask for your LUKS passphrase and then kick you out of the shell.

I stored the LUKS passphrase in my Vaultwarden and used [`rbw`](https://git.tozt.net/rbw/about/) to retrieve it. This allows me to have this oneliner for unlocking the server:

```sh
rbw get 'LUKS myhostname' | ssh root@1.2.3.4 -p 1234 cryptsetup-askpass
```

It only took me three tries to get it right! The first time around I had not enabled swraid support in the initrd, the second time I had the "name" wrong.


## Configuration management

The last bit to the puzzle was the actual configuration management of the running system. Continuously uploading .nix files via `scp` did not sound very appealing to me, and neither did some roundtripping via a Git repository. So I started looking into tools like `deploy-rs` or `NixOps`. Luckily for me, Julia Evans _just_ published [Some notes on NixOS](https://jvns.ca/blog/2024/01/01/some-notes-on-nixos/), in which she notes:

> ... you can just use the built-in `nixos-rebuild`, which has `--target-host` and `--build-host` options so that you can specify which host to build on and deploy to, ...

This was exactly what I needed! And of course, I wanted to use Nix Flakes to manage everything, so my setup now looks like this:

In `flake.nix`:

```nix
{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
    in
    {
      # I also use nix-direnv, so this ensures `nixos-rebuild` is
      # available in my shell when I cd into this folder.
      devShell."${system}" = pkgs.mkShell {
        packages = with pkgs; [ nixos-rebuild ];
      };

      nixosConfigurations.myhostname = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [ ./configuration.nix ];
      };
    };
}
```

And then `configuration.nix` is just more or less the configuration I used during setup (but of course adjusted since).

To deploy changes, I then run:

```sh
nixos-rebuild switch --fast --flake ".#myhostname" --target-host "myhostname" --build-host "myhostname"
```

(okay, to be honest, I wrote a Shell script for that, but you get the point)

Once this is in place, you can even get rid of `/etc/nixos` and `/nix/persist/etc/nixos` on your server; they won't be needed anymore.

## The Future

I have since installed and enabled Tailscale to only allow management access via Tailscale. make sure to persist `/var/lib/tailscale`, It contains the credentials required to reconnect to Tailscale!

```nix
{
  # ...

  services.tailscale = {
    enable = true;
    # Allow full network access from the Tailscale network
    openFirewall = true;
    # Set the required sysctl's to use the server as a subnet router or
    # exit node
    useRoutingFeatures = "server";
  };

  # Persistence
  fileSystems."/var/lib/tailscale" = {
    device = "/nix/persist/var/lib/tailscale";
    fsType = "none";
    options = [ "bind" ];
  };
  
  # We won't be connecting via the public interface anymore so shut
  # that down
  services.openssh.openFirewall = false;

  # ...
}
```

I further plan to apply some of the measures outlined in [Paranoid NixOS Setup](https://xeiaso.net/blog/paranoid-nixos-2021-07-18/). And then of course I have to migrate over all services :-)


## Conclusion

This more or less describes my journey towards my first NixOS server! I hope you could learn something new, and found it interesting.

For me, all in all, this was quite a learning experience. I'm quite fascinated by NixOS' deterministic nature. Unlike other configuration management tools that only manage what you explicitly tell them to manage, _everything_ is always managed. I love it!

However I must say, moving around the Rust ecosystem frequently, I'm quite disappointed at the state of Nix and NixOS documentation. Everything seems fragmented across many different places, style, and content are inconsistent, much of it is outdated, and there is sooooo much tribal knowledge.

The temporary root file system is something I wanted to do for a long time. So far it worked out pretty well! Let's see how I will think about this in a few months :-)
