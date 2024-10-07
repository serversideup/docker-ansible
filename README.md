<p align="center">
		<img src="https://raw.githubusercontent.com/serversideup/docker-ansible/main/.github/img/header.png" width="1280" alt="Docker Images Logo"></a>
</p>
<p align="center">
	<a href="https://github.com/serversideup/docker-ansible/actions/workflows/action_publish-images-production.yml"><img alt="Build Status" src="https://img.shields.io/github/actions/workflow/status/serversideup/docker-ansible/.github%2Fworkflows%2Faction_publish-images-production.yml"></a>
	<a href="https://github.com/serversideup/docker-ansible/blob/main/LICENSE" target="_blank"><img src="https://badgen.net/github/license/serversideup/docker-ansible" alt="License"></a>
	<a href="https://github.com/sponsors/serversideup"><img src="https://badgen.net/badge/icon/Support%20Us?label=GitHub%20Sponsors&color=orange" alt="Support us"></a>
  <br />
  <a href="https://hub.docker.com/r/serversideup/ansible/"><img alt="serversideup/ansible pulls" src="https://img.shields.io/docker/pulls/serversideup/ansible?label=serversideup%2Fansible%20pulls"></a><a href="https://hub.docker.com/r/serversideup/ansible-core/"><img alt="serversideup/ansible-core pulls" src="https://img.shields.io/docker/pulls/serversideup/ansible-core?label=serversideup%2Fansible-core%20pulls"></a>
  <a href="https://serversideup.net/discord"><img alt="Discord" src="https://img.shields.io/discord/910287105714954251?color=blueviolet"></a>
</p>

## Introduction
`serversideup/ansible` is a lightweight solution for running Ansible in a containerized environment. This project builds upon many things we learned from [willhallonline/docker-ansible](https://github.com/willhallonline/docker-ansible). It provides a secure and isolated environment for running Ansible tasks, with support for both Alpine and Debian-based distributions and gives you the flexibility to run Ansible as an unprivileged user without the headaches of proper file permissions.

## Features
- 🐧 **Debian and Alpine** - Choose your OS
- 🐍 **Built on official Python images** - Choose your Python version
- 🔒 **Unprivileged user** - Choose to run as root or an unprivileged user
- 📌 **Pinned Ansible Version** - Set your Ansible version down to the patch version
- 🔧 **Customize your "run as" user** - Customize the username to run as
- 🔑 **Set your own PUID and PGID** - Have the PUID and PGID match your host user
- 📦 **DockerHub and GitHub Container Registry** - Choose where you'd like to pull your image from
- 🤖 **Multi-architecture** - Every image ships with x86_64 and arm64 architectures

## Usage
Getting started is easy. Here's a few tips on how to use this image.

### Choose between `ansible` and `ansible-core`

Our images are available on Docker Hub and GitHub Container Registry 🥳

**DockerHub:**
- [serversideup/ansible](https://hub.docker.com/r/serversideup/ansible)
- [serversideup/ansible-core](https://hub.docker.com/r/serversideup/ansible-core)

**GitHub Container Registry:**
- [ghcr.io/serversideup/ansible](https://github.com/serversideup/docker-ansible/pkgs/container/ansible)
- [ghcr.io/serversideup/ansible-core](https://github.com/serversideup/docker-ansible/pkgs/container/ansible-core)

Versions are made available with `ansible` and `ansible-core`. Everything is versioned appropriately according to the [Ansible release process](https://docs.ansible.com/ansible/latest/reference_appendices/release_and_maintenance.html).

| Variation | Default Latest Image | Description |
| --------- | -------------------- | ----------- |
| `serversideup/ansible-core` |**Debian**: [![DockerHub serversideup/ansible-core](https://img.shields.io/docker/image-size/serversideup/ansible-core/latest)](https://hub.docker.com/r/serversideup/ansible-core)<br>**Alpine**: [![DockerHub serversideup/ansible-core:alpine](https://img.shields.io/docker/image-size/serversideup/ansible-core/alpine)](https://hub.docker.com/r/serversideup/ansible-core/tags?name=alpine) | Runs Ansible with `ansible-core` only. Provides a lightweight installation with basic components, focusing on core automation tasks. Ideal for rapid configuration changes and environments prioritizing simplicity and resource optimization. |
| `serversideup/ansible` | **Debian**: [![DockerHub serversideup/ansible](https://img.shields.io/docker/image-size/serversideup/ansible/latest)](https://hub.docker.com/r/serversideup/ansible)<br>**Alpine**: [![DockerHub serversideup/ansible:alpine](https://img.shields.io/docker/image-size/serversideup/ansible/alpine)](https://hub.docker.com/r/serversideup/ansible/tags?name=alpine) | Comprehensive ecosystem including Ansible Core, Tower, Galaxy, etc. Offers a full package with plugins, dependencies, and modules for diverse automation scenarios across hybrid environments. Debian-based image provides full functionality, while Alpine-based image offers a lightweight alternative. |

### Run a playbook
> [!IMPORTANT]  
> In almost all cases you will need to mount a volume to the Ansible "working directory" (default: `/ansible`) and your SSH configurations (usually `~/.ssh`).

```bash
docker run --rm -it \
  -v "$HOME/.ssh:/home/ansible/.ssh" \
  -v "$(pwd):/ansible" \
  serversideup/ansible:latest ansible-playbook playbook.yml
```

### Change the "run as" user, PUID and PGID

```bash
docker run --rm -it \
  -v "$HOME/.ssh:/home/ansible/.ssh" \
  -v "$(pwd):/ansible" \
  -e PUID=9999 -e PGID=9999 \
  -e RUN_AS_USER=bob \
  serversideup/ansible:latest ansible-playbook playbook.yml
```

### Run a shell
```bash
docker run --rm -it \
  -v "$HOME/.ssh:/home/ansible/.ssh" \
  -v "$(pwd):/ansible" \
  serversideup/ansible:latest /bin/sh
```

### Environment Variables
You can customize the image easily with the following environment variables:

| Variable | Default | Description |
| -------- | ------- | ----------- |
| `PUID` | `1000` | The user ID of the unprivileged user |
| `PGID` | `1000` | The group ID of the unprivileged user |
| `RUN_AS_USER` | `ansible` | The username of the unprivileged user |
| `DEBUG` | `false` | Enable debug output of container startup |


## Resources
- **[DockerHub](https://hub.docker.com/r/serversideup/ansible)** to browse the images.
- **[Discord](https://serversideup.net/discord)** for friendly support from the community and the team.
- **[GitHub](https://github.com/serversideup/docker-ansible)** for source code, bug reports, and project management.
- **[Get Professional Help](https://serversideup.net/professional-support)** - Get video + screen-sharing help directly from the core contributors.

## Contributing
As an open-source project, we strive for transparency and collaboration in our development process. We greatly appreciate any contributions members of our community can provide. Whether you're fixing bugs, proposing features, improving documentation, or spreading awareness - your involvement strengthens the project. Please review our [code of conduct](./.github/code_of_conduct.md) to understand how we work together respectfully.

- **Bug Report**: If you're experiencing an issue while using these images, please [create an issue](https://github.com/serversideup/docker-ansible/issues/new/choose).
- **Feature Request**: Make this project better by [submitting a feature request](https://github.com/serversideup/docker-ansible/discussions/).
- **Documentation**: Improve our documentation by [submitting a documentation change](./README.md).
- **Community Support**: Help others on [GitHub Discussions](https://github.com/serversideup/docker-ansible/discussions) or [Discord](https://serversideup.net/discord).
- **Security Report**: Report critical security issues via [our responsible disclosure policy](https://www.notion.so/Responsible-Disclosure-Policy-421a6a3be1714d388ebbadba7eebbdc8).

Need help getting started? Join our Discord community and we'll help you out!

<a href="https://serversideup.net/discord"><img src="https://serversideup.net/wp-content/themes/serversideup/images/open-source/join-discord.svg" title="Join Discord"></a>

## Our Sponsors
All of our software is free an open to the world. None of this can be brought to you without the financial backing of our sponsors.

<p align="center"><a href="https://github.com/sponsors/serversideup"><img src="https://521public.s3.amazonaws.com/serversideup/sponsors/sponsor-box.png" alt="Sponsors"></a></p>

### Black Level Sponsors
<a href="https://sevalla.com"><img src="https://serversideup.net/wp-content/uploads/2024/10/sponsor-image.png" alt="Sevalla" width="546px"></a>

#### Bronze Sponsors
<!-- bronze -->No bronze sponsors yet. <a href="https://github.com/sponsors/serversideup">Become a sponsor →</a><!-- bronze -->

#### Individual Supporters
<!-- supporters --><a href="https://github.com/GeekDougle"><img src="https://github.com/GeekDougle.png" width="40px" alt="GeekDougle" /></a>&nbsp;&nbsp;<a href="https://github.com/JQuilty"><img src="https://github.com/JQuilty.png" width="40px" alt="JQuilty" /></a>&nbsp;&nbsp;<a href="https://github.com/pferreirafabricio"><img src="https://github.com/pferreirafabricio.png" width="40px" alt="pferreirafabricio" /></a>&nbsp;&nbsp;<!-- supporters -->

#### Special thanks
We'd like to specifically thank a few folks for taking the time for being a sound board that deeply influenced the direction of this project.

Please check out all of their work:
- [Chris Fidao](https://twitter.com/fideloper)
- [Joel Clermont](https://twitter.com/joelclermont)
- [Patricio](https://twitter.com/PatricioOnCode)

## About Us
We're [Dan](https://twitter.com/danpastori) and [Jay](https://twitter.com/jaydrogers) - a two person team with a passion for open source products. We created [Server Side Up](https://serversideup.net) to help share what we learn.

<div align="center">

| <div align="center">Dan Pastori</div>                  | <div align="center">Jay Rogers</div>                                 |
| ----------------------------- | ------------------------------------------ |
| <div align="center"><a href="https://twitter.com/danpastori"><img src="https://serversideup.net/wp-content/uploads/2023/08/dan.jpg" title="Dan Pastori" width="150px"></a><br /><a href="https://twitter.com/danpastori"><img src="https://serversideup.net/wp-content/themes/serversideup/images/open-source/twitter.svg" title="Twitter" width="24px"></a><a href="https://github.com/danpastori"><img src="https://serversideup.net/wp-content/themes/serversideup/images/open-source/github.svg" title="GitHub" width="24px"></a></div>                        | <div align="center"><a href="https://twitter.com/jaydrogers"><img src="https://serversideup.net/wp-content/uploads/2023/08/jay.jpg" title="Jay Rogers" width="150px"></a><br /><a href="https://twitter.com/jaydrogers"><img src="https://serversideup.net/wp-content/themes/serversideup/images/open-source/twitter.svg" title="Twitter" width="24px"></a><a href="https://github.com/jaydrogers"><img src="https://serversideup.net/wp-content/themes/serversideup/images/open-source/github.svg" title="GitHub" width="24px"></a></div>                                       |

</div>

### Find us at:

* **📖 [Blog](https://serversideup.net)** - Get the latest guides and free courses on all things web/mobile development.
* **🙋 [Community](https://community.serversideup.net)** - Get friendly help from our community members.
* **🤵‍♂️ [Get Professional Help](https://serversideup.net/professional-support)** - Get video + screen-sharing support from the core contributors.
* **💻 [GitHub](https://github.com/serversideup)** - Check out our other open source projects.
* **📫 [Newsletter](https://serversideup.net/subscribe)** - Skip the algorithms and get quality content right to your inbox.
* **🐥 [Twitter](https://twitter.com/serversideup)** - You can also follow [Dan](https://twitter.com/danpastori) and [Jay](https://twitter.com/jaydrogers).
* **❤️ [Sponsor Us](https://github.com/sponsors/serversideup)** - Please consider sponsoring us so we can create more helpful resources.

## Our products
If you appreciate this project, be sure to check out our other projects.

### 📚 Books
- **[The Ultimate Guide to Building APIs & SPAs](https://serversideup.net/ultimate-guide-to-building-apis-and-spas-with-laravel-and-nuxt3/)**: Build web & mobile apps from the same codebase.
- **[Building Multi-Platform Browser Extensions](https://serversideup.net/building-multi-platform-browser-extensions/)**: Ship extensions to all browsers from the same codebase.

### 🛠️ Software-as-a-Service
- **[Bugflow](https://bugflow.io/)**: Get visual bug reports directly in GitHub, GitLab, and more.
- **[SelfHost Pro](https://selfhostpro.com/)**: Connect Stripe or Lemonsqueezy to a private docker registry for self-hosted apps.

### 🌍 Open Source
- **[AmplitudeJS](https://521dimensions.com/open-source/amplitudejs)**: Open-source HTML5 & JavaScript Web Audio Library.
- **[Spin](https://serversideup.net/open-source/spin/)**: Laravel Sail alternative for running Docker from development → production.
- **[Financial Freedom](https://github.com/serversideup/financial-freedom)**: Open source alternative to Mint, YNAB, & Monarch Money.