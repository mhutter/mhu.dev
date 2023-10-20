+++
title = "Working with Git submodules"
summary = "Primer on how to use Git submodules"
aliases = ["posts/working-with-git-submodules"]
[taxonomies]
tags = ["git"]
+++

Here's a quick primer on how to work with Git submodules!

<!-- more -->

## Adding Submodules to your project

```sh
git submodule add repo_url [directory]
git commit -m 'added xyz as a dependency'
```

`git submodule add` works like `git clone`, so the directory name can be ommited. The changes will automatically be added to the index, so you can commit them right away!

## Cloning a repository with Submodules

```sh
git clone repo_url --recursive
```

This will first clone the repo, and then initialize and update (read on) all submodules.

If you forget the `--recursive` flag when cloning, or when pulling in commits that add a Submodule, you have to do two steps: initialize, update:

```sh
git submodule init
git submodule update
```

This will create the required directories and then pull in the other repos.

## Update Submodules

Easy:

```sh
git submodule update --remote
git add submodule_dir
git commit ...
```

That’s it!

For more in-depth information on Git Submodules, read the [official documentation](https://git-scm.com/book/en/v2/Git-Tools-Submodules)
