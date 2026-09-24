# Security Policy

We only build images on versions that still get security fixes from their maintainers.

## Supported versions

These versions are built and rebuilt every week.

| Component | Supported versions |
| --- | --- |
| `ansible-core` | 2.21, 2.20, 2.19 |
| `ansible` | 14, 13, 12 |
| Python | 3.14, 3.13, 3.12, 3.11 |
| Debian | trixie, bookworm |
| Alpine | alpine3.24, alpine3.23 |

Not every combination is built. Each Ansible version only ships with the Python versions it supports. See [`ansible-versions.yml`](ansible-versions.yml) for the full list.

## How we choose versions

We keep building a version while **both** of these are true:

1. Its maintainer still releases security fixes for it.
2. The [official Python image](https://hub.docker.com/_/python) still publishes updates for it.

If either one stops, we stop building that version.

## When a version reaches end of life

- We remove it from our builds.
- **Old tags are not deleted.** You can still pull them, so you have time to upgrade.
- **Old tags do not get security fixes.** They are frozen as they were on their last build.
- Move to a supported version as soon as you can.

> [!TIP]
> Use a tag like `latest`, `alpine`, `debian`, or `2.21` (for `ansible-core`) if you want to stay on a supported version automatically.

## Weekly rebuilds

Production images are rebuilt every **Tuesday at 04:00 UTC**. Each rebuild picks up the latest patches for:

- Ansible (latest patch release)
- Python
- The base operating system

## Where our support dates come from

| Component | Official source |
| --- | --- |
| Ansible and `ansible-core` | [Ansible release and maintenance](https://docs.ansible.com/ansible/latest/reference_appendices/release_and_maintenance.html) |
| Python | [Python versions](https://devguide.python.org/versions/) |
| Debian | [Debian LTS](https://wiki.debian.org/LTS) |
| Alpine | [Alpine releases](https://alpinelinux.org/releases/) |
| Python Docker image | [docker-library/python](https://github.com/docker-library/python/blob/master/versions.json) |

## Report a vulnerability

**Do not open a public issue or pull request.** It could expose the problem before it is fixed.

Use [GitHub's private vulnerability reporting](https://github.com/serversideup/docker-ansible/security/advisories/new) instead. Please include:

- The image tag or digest (for example, `serversideup/ansible:14-alpine3.24@sha256:...`)
- Steps to reproduce the problem
- What an attacker could do with it

### Report it here

Problems in things we write and ship:

- Scripts in `src/`, like the entrypoint and helper scripts
- Default settings, users, and file permissions in the image
- Our build and publish workflows

### Report it upstream

Problems in software we package but do not maintain:

| Component | Where to report |
| --- | --- |
| Ansible | [Ansible security](https://docs.ansible.com/ansible/latest/community/reporting_bugs_and_features.html#security-bugs) |
| Python | [Python security](https://www.python.org/dev/security/) |
| Debian packages | [Debian security team](https://www.debian.org/security/) |
| Alpine packages | [Alpine security](https://security.alpinelinux.org/) |

If a fix is already released upstream, you don't need to report it to us. Our weekly rebuild will pick it up.
