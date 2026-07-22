---
title: "Your pipeline is holding a key that never expires"
date: 2026-07-22
author: David — CODACON Inc.
description: "Static AWS access keys in CI have no expiry and no blast radius. GitHub's OIDC provider replaces them with a short-lived session scoped to one repository and one branch."
license: CC-BY-4.0
SPDX-License-Identifier: CC-BY-4.0
canonical: https://codacon.net/notes/oidc-instead-of-keys
keywords: AWS, GitHub Actions, OIDC, IAM, CI/CD security
document: CODACON-SEC-2026-07
reading_time: 6 min
---

Every `AWS_SECRET_ACCESS_KEY` sitting in a GitHub Actions secret is a credential with no expiry, no session context, and no way to tell an audit which run used it. There has been a better option since 2021.

Ask any team when they last rotated the deploy key in their CI. The honest answer is usually the day they created it. A static IAM access key has no lifetime — it works until a human remembers to revoke it, which means its real expiry date is the day someone leaves the company, or the day it turns up in a log aggregator.

GitHub Actions can act as an OpenID Connect identity provider. AWS can trust that provider directly. The runner presents a signed token describing exactly which repository, which branch, and which workflow is asking; AWS exchanges it for a session that dies within the hour. No secret is stored anywhere.

## Register the provider once per account

AWS needs to know the issuer exists. One IAM identity provider per account, pointing at GitHub's issuer URL with `sts.amazonaws.com` as the audience:

```
aws iam create-open-id-connect-provider \
  --url https://token.actions.githubusercontent.com \
  --client-id-list sts.amazonaws.com
```

If your organisation uses GitHub Enterprise with a custom issuer, the URL changes and every trust policy below has to change with it. Check before you write the role.

## Scope the trust policy to one branch

This is where most implementations quietly stay insecure. The token's `sub` claim encodes the repository and the git ref. Pin it with `StringEquals`:

```
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {
      "Federated": "arn:aws:iam::111122223333:oidc-provider/token.actions.githubusercontent.com"
    },
    "Action": "sts:AssumeRoleWithWebIdentity",
    "Condition": {
      "StringEquals": {
        "token.actions.githubusercontent.com:aud": "sts.amazonaws.com",
        "token.actions.githubusercontent.com:sub": "repo:codacon/infra:ref:refs/heads/main"
      }
    }
  }]
}
```

> **Failure mode:** A trust policy written as `StringLike` with `repo:yourorg/*` will accept a token from any repository in the organisation — including one a contractor forked yesterday. If you must use a wildcard, wildcard the ref, never the repo.

## Grant the workflow permission to request a token

The runner cannot mint an OIDC token unless the job asks for it. The `id-token` permission is not granted by default:

```
permissions:
  id-token: write   # request the OIDC token
  contents: read    # checkout only

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: arn:aws:iam::111122223333:role/gha-infra-deploy
          aws-region: ca-central-1
          role-duration-seconds: 900
```

Set `permissions` at job level rather than workflow level, so a test job in the same file cannot request a token it has no reason to hold.

## Cutting over without a deployment freeze

1. Create the role and trust policy alongside the existing key. Nothing breaks; the key still works.
2. Switch one low-risk workflow to `configure-aws-credentials` and confirm the deploy succeeds.
3. Watch CloudTrail for `AssumeRoleWithWebIdentity` events and check the session name maps to the run you expect.
4. Migrate the remaining workflows, then set the old access key to *Inactive* — not deleted.
5. Wait a full release cycle. If nothing fails, delete the key and remove the GitHub secret.

Step 4 matters more than it looks. Deactivating rather than deleting means CloudTrail still records attempts to use the key, which tells you whether anything outside your CI was quietly depending on it. That is usually how you discover the laptop cron job nobody documented.

## What this does not solve

OIDC removes the stored secret. It does not reduce what the role can do once assumed. A short-lived session with `AdministratorAccess` is still an administrator. The permissions policy attached to the role deserves the same scrutiny as the trust policy — and it is worth reading the two as a pair, because the trust policy answers *who* and the permissions policy answers *what*.

It also does nothing about third-party actions. Any `uses:` line in a job that holds an OIDC token runs with access to that token. Pin actions to a full commit SHA rather than a tag.
