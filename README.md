# NASA-PDS Drupal base image

`docker.io/nasapds/drupal` is the PHP + Apache base image for the PDS Portal
([NASA-PDS/portal-drupal](https://github.com/NASA-PDS/portal-drupal)). It
replaces the official `drupal:10-php8.3-apache-trixie` image as the `FROM` of
portal-drupal's `Dockerfile`.


## What's in it

- PHP 8.3 with mod_php under Apache, on Debian 13 (trixie)
- PHP extensions `gd` (AVIF, FreeType, JPEG, PNG, WebP), `pdo_mysql`,
  `pdo_pgsql` and `zip`, plus `opcache` from the PHP image
- Apache `rewrite` and `expires` modules enabled
- Drupal's recommended `opcache` settings and `output_buffering=true`
- Composer 2 at `/usr/local/bin/composer`, with `COMPOSER_ALLOW_SUPERUSER=1`
- `WORKDIR /opt/drupal`, with `/var/www/html` symlinked to `/opt/drupal/web`
- `/opt/drupal/vendor/bin` on `PATH`

Only `linux/amd64` is built, which is what runs on AWS EC2.


## How it differs from the official image

- **No Drupal core.** The official image runs
  `composer create-project drupal/recommended-project` into `/opt/drupal`.
  portal-drupal bind-mounts (or, for CI, `COPY`s) its own Composer project
  there, which hides the baked-in copy, so this image ships an empty
  `/opt/drupal/web` instead. Drupal and its dependencies come from the site's
  own `composer.lock`. As a result, the image doesn't need rebuilding for
  Drupal core releases.
- **No PHP execution at build time.** The PHP extension directory comes from
  `php-config --extension-dir` instead of `php -r`, because PHP CLI crashes
  under QEMU when building `linux/amd64` on Apple Silicon with Podman. See
  portal-drupal's `docs/pds/provided-ami-compatibility.md`.


## Tags

| Tag | Meaning |
|-----|---------|
| `php8.3-apache-trixie` | Rolling: always the most recent build |
| `php8.3-apache-trixie-YYYYMMDD` | Immutable: the build from that date, for pinning or rolling back |

Use the fully qualified name, `docker.io/nasapds/drupal:…`. Podman on the EC2
AMI does not assume Docker Hub for short names.


## Building and testing locally

With Docker:
```bash
docker buildx build --platform linux/amd64 --load --tag nasapds/drupal:dev .
tests/smoke.sh nasapds/drupal:dev
```

With Podman:
```bash
podman build --platform linux/amd64 --tag nasapds/drupal:dev .
CONTAINER_ENGINE=podman tests/smoke.sh localhost/nasapds/drupal:dev
```

To try a local build in portal-drupal, temporarily change its `FROM` to the
local tag.


## Publishing

`.github/workflows/publish.yaml` builds the image, runs `tests/smoke.sh`
against it, and pushes both tags to Docker Hub. It runs on:

- pushes to `main` (build, test, push)
- pull requests to `main` (build and test only, no push)
- a weekly schedule (Mondays 06:17 UTC), which rebuilds without cache to pick
  up upstream PHP patch releases and Debian security fixes
- manual dispatch

The repository needs these Actions secrets:

| Secret | Value |
|--------|-------|
| `DOCKERHUB_USERNAME` | A Docker Hub account with push access to `nasapds/drupal` |
| `DOCKERHUB_TOKEN` | A Docker Hub access token for that account, with read & write scope |


## Changing the PHP version

The Dockerfile takes a `PHP_VERSION` build argument (default `8.3`). The
workflow sets the same value in its `env:` block, and that value also goes
into the tag names. Change both together. Check portal-drupal's `Dockerfile`
too, because it builds its `FROM` reference from its own `PHP_VERSION`
argument.
