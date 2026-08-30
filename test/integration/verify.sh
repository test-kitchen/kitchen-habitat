#!/usr/bin/env bash
#
# Asserts that the converge did what the provisioner claims it does.
#
# Run by the `shell` verifier, which executes locally -- which is the instance
# itself, because these suites use the `exec` driver. KITCHEN_SUITE is exported
# by the verifier.
set -euo pipefail

export PATH="/bin:/usr/bin:${PATH}"

fail() {
  echo "FAIL: $*" >&2
  echo "--- hab svc status ---" >&2
  sudo -E hab svc status >&2 || true
  echo "--- hab-sup journal (last 50 lines) ---" >&2
  sudo journalctl -u hab-sup -n 50 --no-pager >&2 || true
  exit 1
}

pass() { echo "ok: $*"; }

# --- Assertions that hold for every suite ------------------------------------

command -v hab >/dev/null 2>&1 || fail "the hab CLI is not on PATH"
pass "hab CLI installed: $(hab --version)"

[ -f /etc/systemd/system/hab-sup.service ] || fail "no hab-sup systemd unit was written"
pass "hab-sup systemd unit written"

systemctl is-active --quiet hab-sup || fail "the hab-sup service is not running"
pass "hab-sup service is running"

grep -q 'HAB_LICENSE=accept' /etc/systemd/system/hab-sup.service ||
  fail "hab_license was not passed to the supervisor"
pass "HAB_LICENSE passed to the supervisor"

getent group hab >/dev/null 2>&1 || fail "the hab group was not created"
id -u hab >/dev/null 2>&1 || fail "the hab user was not created"
pass "hab user and group exist"

sudo -E hab svc status >/dev/null 2>&1 || fail "the supervisor is not answering hab svc status"
pass "supervisor answers hab svc status"

# --- Per-suite assertions ----------------------------------------------------

case "${KITCHEN_SUITE}" in
default)
  sudo -E hab svc status | grep -q 'core/redis' || fail "core/redis was not loaded"
  pass "core/redis is loaded"
  ;;

user-toml)
  sudo -E hab svc status | grep -q 'core/redis' || fail "core/redis was not loaded"
  pass "core/redis is loaded"

  [ -f /hab/user/redis/config/user.toml ] ||
    fail "user.toml was not installed into /hab/user/redis/config"
  sudo grep -q 'port = 6380' /hab/user/redis/config/user.toml ||
    fail "/hab/user/redis/config/user.toml does not hold our settings"
  pass "user.toml installed from user_toml_name"

  grep -q -- '--listen-http 0.0.0.0:9631' /etc/systemd/system/hab-sup.service ||
    fail "hab_sup_listen_http was not passed to the supervisor"
  pass "supervisor started with the configured HTTP gateway"
  ;;

library-package)
  sudo -E hab pkg path core/jq-static >/dev/null 2>&1 ||
    fail "core/jq-static was not installed"
  pass "core/jq-static is installed"

  if sudo -E hab svc status 2>/dev/null | grep -q 'jq-static'; then
    fail "a package with no run hook was loaded as a service"
  fi
  pass "a package with no run hook was left unloaded"
  ;;

*)
  fail "no assertions defined for suite ${KITCHEN_SUITE}"
  ;;
esac

echo "All assertions passed for suite ${KITCHEN_SUITE}."
