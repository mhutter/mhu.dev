+++
title = "Developing NixOS (and Home Manager) Modules"
[taxonomies]
tags = ["nixos", "nix"]
+++

If you use NixOS or Home Manager, chances are that you have (unknowingly) created a NixOS module. In this post, I'll document my learnings around how they work, and how to easily test them in isolation.

<!-- more -->

Also note that for the sake of my sanity, I'll only talk about NixOS in this post, but the same concepts also apply to HomeManager.

# What are modules?

In short, modules are isolated components that make up NixOS.

If you have moved parts of your NixOS configuration to a separate file, and then included it again using `imports = [ ... ];`, then you have written a module!

Because that's what modules are: Nix expressions that import other modules, define options other modules can set, and that in turn set options in other modules.

# The basics

The most basic module looks like this:

```nix
{
  services.openssh.enable = true;
}
```

But to show the full structure, a minimal example would _actually_ look like this:

```nix
{ ... }:

{
  imports = [ ];

  options = { };

  config = {
    services.openssh.enable = true;
  };
}
```

- The Nix expression can be a function which will then be called. In this example, we ignore all arguments, but the following commonly used things are (amongst others) passed to all modules:
  - `lib` - the nixpkgs library
  - `config` - the final configuration of all the modules
  - `options` - options declared in all modules
  - `pkgs` - nixpkgs packages - though this is specific

* The resulting expression has three valid attributes, all of which can be omitted if empty:
  - `imports` allows you to import other modules
  - `options` to define our own options
  - `config` to set options in other modules

# Defining Options

In modules, we can define our own options:

```nix
{ lib, config, ... }:

let
  # Convention to access "our own" configuration
  cfg = config.mymodule;

in
{
  options = {
    mymodule = {
      firstName = lib.mkOption {
        description = "Your first name";
        type = lib.types.str;
        default = "John";
      };
      lastName = lib.mkOption {
        description = "Your last name";
        type = lib.types.str;
        default = "Doe";
      };
      fullName = lib.mkOption {
        type = lib.types.str;
      };
    };
  };

  config = {
    mymodule.fullName = "${cfg.firstName} ${cfg.lastName}";
  };
}
```

Once imported, other modules can now set `mymodule.firstName`, and it will be available to us as `config.mymodule.firstName` (or `cfg.firstName` thanks to the `let` binding).

Options should always have a type to prevent errors. See [NixOS: Option Types](https://nixos.org/manual/nixos/stable/#sec-option-types) for a full list of types. Note that HomeManager brings a couple of [extra option types](https://nix-community.github.io/home-manager/index.xhtml#sec-option-types).

# Testing modules

Now I love to iterate quickly on my code, so rebuilding my entire NixOS configuration is not practical. I also want to inspect the output of my modules without having to check what changes Nix actually applied to the system.

So let's create a small "NixOS module sandbox" in `sandbox.nix`:

```nix
(import <nixpkgs/lib>).evalModules {
  modules = [{
    # import your module here
    imports = [ ./mymodule.nix ];

    # For testing you can set any configs here
    mymodule.firstName = "Jaques";
  }];
}
```

If we put our example module from above in `mymodule.nix`, we can now evaluate everything:

```sh
nix-instantiate --eval ./sandbox.nix --strict -A config
```

Some notes on the options used

- `--eval` can be left off if `sandbox.nix` is called `default.nix` instead
- `--strict` causes the whole expression to be evaluated recursively. Since Nix is lazy, we would just see `<CODE>` instead.
- `-A config` selects the `config` attribute of the resulting expression. You can leave it off to get the _whole_ expression (not very useful), or set it to something like `config.mymodule.fullName` to get a specific value.
- `--json` can be used to output JSON instead of a Nix expression, but that only works if the output does not contain any lambdas or functions. Actually, this helped me find a bug once, where I only referenced a function instead of calling it!

And then using a bit of `entr` and `jq`, we get:

```sh
ls -1 *.nix | \
entr sh -c 'nix-instantiate --eval ./sandbox.nix --strict -A config --json | jq'
```

# Further reading

- [Module system — nix.dev documentation](https://nix.dev/tutorials/module-system/index.html)
- ["Writing NixOS Modules" in the NixOS manual](https://nixos.org/manual/nixos/stable/index.html#sec-writing-modules)
- ["Writing Home Manager Modules" in the Home Manager manual](https://nix-community.github.io/home-manager/index.xhtml#ch-writing-modules)
