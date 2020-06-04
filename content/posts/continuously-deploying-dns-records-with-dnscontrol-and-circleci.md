---
date: 2018-04-20T13:37:00+01:00
title: Continuously Deploying DNS records with DnsControl and CircleCI
summary: How to continuously deploy DNS records to Google Cloud DNS using CircleCI
tags: [dns, dnscontrol, circleci, ci/cd]
---

In the [previous post]({{< ref "managing-dns-records-the-devops-way.md" >}}) I gave a quick introduction to [DnsControl](https://stackexchange.github.io/dnscontrol/), what it does and how it works. In this post, I'll show you how to continuously deploy your changes to [Google Cloud DNS](https://cloud.google.com/dns/) using [CircleCI](https://circleci.com/).

The goal is to have a Pipeline that works like this: On each push, run `dnscontrol check` to verify the file is valid, `dnscontrol preview` to make sure all configuration is correct (credentials, zones, ...). And if we're on the `master` branch (and the previous steps were succesful) `dnscontrol push` the changes to our DNS provider.

First, we need a container containing `dnscontrol` to run on CircleCI. Luckily for us there is an official one on Docker Hub: [stackexchange/dnscontrol](https://hub.docker.com/r/stackexchange/dnscontrol/).

Next we need a `.circleci/config.yml` file:

```yaml
---
version: 2

# Job definitions
jobs:
  check:
    docker:
      - image: stackexchange/dnscontrol
    steps:
      - checkout
      - run: dnscontrol check

  preview:
    docker:
      - image: stackexchange/dnscontrol
    steps:
      - checkout
      - run: dnscontrol preview

  deploy:
    docker:
      - image: stackexchange/dnscontrol
    steps:
      - checkout
      - run: dnscontrol push

# Definitions of the Workflow, our "Pipeline"
workflows:
  version: 2
  check-preview-deploy:
    jobs:
      - check
      - preview
      - deploy:
          requires:
            - check
            - preview
          filters: # only deploy from master branch
            branches:
              only: master
```

Now we have one problem left: We have to provide the credentials. Fortunately enough, the values in `creds.json` can contain ENV var names which dnscontrol then properly reads from the environment:

```json
{
  "gcloud": {
    "type": "service_account",
    "project_id": "$GCLOUD_PROJECT_ID",
    "private_key": "$GCLOUD_PRIVATE_KEY",
    "client_email": "$GCLOUD_CLIENT_EMAIL"
  }
}
```

Unfortunately this did not work as expected. Google Cloud uses Private Key authentication for their service accounts, and I was not able to properly set an env var with the key in a for that dnscontrol could understand.

So instead I came up with something else:

0. Create the `creds.json` file locally
0. `base64` encode the file
0. On CircleCI, set an env var `$CREDS` to the encoded string
0. During builds, decode and write the data to `creds.json`

As only the `preview` and `push` commands require authentication, we only have to write the file during the `preview` and `deploy` jobs, for example:

```yaml
# ...
  deploy:
    docker:
      - image: stackexchange/dnscontrol
    steps:
      - checkout
      - run: echo "$CREDS" | base64 -d > creds.json
      - run: dnscontrol push
# ...
```

The final version of my `.circleci/config.yml` file can be seen [on GitHub](https://github.com/mhutter/dns/blob/09dcf6fc0aab3cf7fe0929edd19099739d5ab690/.circleci/config.yml).

## Bonus

Some people like to be a bit more careful, so they want to manually confirm a deployment. This can be done with a "hold" step in our workflow. Adjust the `workflows` section of the `config.yml` like this:

```yaml
workflows:
  version: 2
  check-preview-hold-deploy:
    jobs:
      - check
      - preview
      - hold:
          type: approval
          requires:
            - check
            - preview
          filters:
            branches:
              only: master
      - deploy:
          filters: &only_master
            branches:
              only: master
```

Now the workflow will pause after the `check` and `preview` steps.

Happy deploying continuously!
