+++
title = "Continuous Deployment with Github Pages"
description = "How to let Travis CI merge into master on successful builds"
[taxonomies]
tags = ["ci/cd"]
+++

Or **how to let Travis-CI merge into master if the build is successful**.

It is way easier than I thought.


## Prerequisites
* The `travis` gem
* Travis-CI integration up and running (ie `.travis.yml` is set up).


## Step 1: Acquire Github Access Token
This is required because we don't want to write our Github username and password anywhere.
Go to your [Github Application Settings](https://github.com/settings/applications) and create a new Token.


## Step 2: Encrypt the token
Even the Token is not something to post on your Twitter.

```bash
travis encrypt -a - GITHUB_TOKEN=your_generated_token
```

Your token will be encrypted and automatically added to your .travis.yml file.


## Step 3: Add some magic to your Travis config
'nuff said. Add these lines to .travis.yml (note this are only two lines):

```yaml
after_success:
- '[ "${TRAVIS_BRANCH}" = "stable" ] && git push https://${GITHUB_TOKEN}:x-oauth-basic@github.com/${TRAVIS_REPO_SLUG}.git HEAD:master'
```

Now for some explanation:
The first part, `[ "${TRAVIS_BRANCH}" = "stable" ] &&` only runs the following command if the current branch name is "stable". You can omit this if you want to merge from ANY branch, or change it to use another branch.

The second part, `git push https://${GITHUB_TOKEN}:x-oauth-basic@github.com/${TRAVIS_REPO_SLUG}.git HEAD:master'` actually pushes the currently checked out state into master.
* `$GITHUB_TOKEN` holds our Token from above
* `$TRAVIS_REPO_SLUG` holds 'github_username/github_repo_name' (in my case this is `mhutter/mhutte.github.io`).

+++

## Back story

To ensure new pages don't break Jekyll (as I managed earlier this month), I use [Travis-CI](https://travis-ci.org/).

I started working on a development branch and only merging into master after the Travis build succeeded. However, being the lazy guy I am I asked myself = "Wouldn't it be nice to let Travis automatically merge into master if the build succeeds?"
