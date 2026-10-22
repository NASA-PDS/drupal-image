#!/usr/bin/env bash
#
# Smoke-test a built nasapds/drupal image.
#
# Usage: tests/smoke.sh IMAGE
#
# Set CONTAINER_ENGINE=podman to test with Podman instead of Docker.

set -euo pipefail

image="${1:?usage: $0 IMAGE}"
engine="${CONTAINER_ENGINE:-docker}"

failures=0

run() {
  "$engine" run --rm --platform linux/amd64 "$image" "$@"
}

check() {
  local description="$1"
  shift
  if "$@"; then
    echo "ok   - $description"
  else
    echo "FAIL - $description"
    failures=$((failures + 1))
  fi
}

modules="$(run php -m)"
for extension in gd pdo_mysql pdo_pgsql zip 'Zend OPcache'; do
  check "PHP extension: $extension" grep -qx "$extension" <<<"$modules"
done

gd_info="$(run php -r 'foreach (gd_info() as $k => $v) { echo $k, "=", var_export($v, true), PHP_EOL; }')"
for feature in 'FreeType Support' 'JPEG Support' 'PNG Support' 'WebP Support' 'AVIF Support'; do
  check "gd: $feature" grep -qx "$feature=true" <<<"$gd_info"
done

check "composer runs" run sh -c 'composer --version --no-interaction >/dev/null 2>&1'

apache_modules="$(run apache2ctl -M 2>/dev/null)"
for module in rewrite_module expires_module php_module; do
  check "Apache module: $module" grep -q "^ *$module " <<<"$apache_modules"
done

check "/var/www/html -> /opt/drupal/web" test "$(run readlink /var/www/html)" = /opt/drupal/web
check "workdir is /opt/drupal" test "$(run pwd)" = /opt/drupal
# The CLI SAPI forces output_buffering off, so check the ini file instead.
drupal_ini=/usr/local/etc/php/conf.d/docker-php-drupal-recommended.ini
check "output_buffering ini is loaded" grep -q "$drupal_ini" <<<"$(run php --ini)"
check "output_buffering ini enables it" grep -qx 'output_buffering=true' <<<"$(run cat "$drupal_ini")"
check "/opt/drupal/vendor/bin is on PATH" grep -q ':/opt/drupal/vendor/bin$' <<<"$(run printenv PATH)"

if ((failures > 0)); then
  echo "$failures check(s) failed"
  exit 1
fi
echo "All checks passed"
