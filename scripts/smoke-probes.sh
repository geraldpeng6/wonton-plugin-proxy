# shellcheck shell=bash
# The proxy has a shared controller identity, not application user accounts.
# A valid controller response proves the gateway supplied its private bearer credential.
web_assert() { grep -q '<title>Proxy</title>'; }

identity_check() {
  local reply
  reply="$(dweb /version -H 'Authorization: Bearer obsolete-browser-token')" || return 1
  jq -e '.meta == true and (.version | startswith("v"))' <<<"$reply" >/dev/null || return 1
  reply="$(dweb /subscription/status)" || return 1
  jq -e '.configured == false and .nodes == 0' <<<"$reply" >/dev/null
}
