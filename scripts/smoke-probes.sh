# shellcheck shell=bash
# The proxy has a shared controller identity, not application user accounts.
# A valid controller response proves the gateway supplied its private bearer credential.
marker_file() { # SMOKE_STATE 在套件里是状态目录（e2e 传的是标记文件本身），标记放对应路径
  if [[ -d "$SMOKE_STATE" ]]; then printf '%s' "$SMOKE_STATE/proxy-marker"; else printf '%s' "${SMOKE_STATE}.marker"; fi
}

web_assert() { grep -q '<title>Proxy</title>'; }

identity_check() {
  local reply
  reply="$(dweb /version -H 'Authorization: Bearer obsolete-browser-token')" || return 1
  jq -e '.meta == true and (.version | startswith("v"))' <<<"$reply" >/dev/null || return 1
  reply="$(dweb /subscription/status)" || return 1
  # 有升级起点时数据目录里已经有订阅（configured=true、可能有节点），这里只看控制器认不认这个身份。
  jq -e '(.configured | type) == "boolean" and (.nodes | type) == "number"' <<<"$reply" >/dev/null
}

# 数据：用户数据就是订阅地址——网页接口 /subscription/save 把它落进数据目录的 subscription.url，
# 代理配置随之生成；/subscription/status 的 configured 字段是应用自己的确认。data_write 存一个
# 不可达的示例地址（应用照常落盘，只把抓取失败如实报成 502），重装后 configured 仍是 true。
proxy_save() { # <url>：经网页链路存订阅（网关补控制器凭据，Caddy 校验后转给订阅服务）
  curl -sS --noproxy '*' -b "${SMOKE_JAR:-}" -w '\n%{http_code}' -X POST \
    -H "Origin: ${SMOKE_WEB_URL%/}" -H 'Content-Type: application/x-www-form-urlencoded' \
    --data-urlencode "url=$1" "${SMOKE_WEB_URL%/}/subscription/save"
}

proxy_status() { dweb /subscription/status; }

data_write() {
  local marker out code body
  marker="http://192.0.2.10/wonton-smoke-$(od -An -N4 -tx4 /dev/urandom | tr -d ' \n').yaml"
  out="$(proxy_save "$marker")" || { echo "存订阅请求失败：$out"; return 1; }
  code="${out##*$'\n'}"
  body="${out%$'\n'*}"
  case "$code" in
    200) : ;;  # 抓取成功，订阅已配置
    502) grep -q 'URL saved' <<<"$body" || { echo "502 但没说 URL 已保存：$body"; return 1; } ;;
    *) echo "存订阅返回 $code：$body"; return 1 ;;
  esac
  body="$(proxy_status)" || { echo "读不到订阅状态：$body"; return 1; }
  jq -e '.configured == true' <<<"$body" >/dev/null || { echo "应用没确认订阅已保存：$body"; return 1; }
  printf '%s' "$marker" >"$(marker_file)"
}

data_check() {
  local body
  [[ -s "$(marker_file)" ]] || { echo "没有 data_write 留下的标记"; return 1; }
  body="$(proxy_status)" || { echo "读不到订阅状态：$body"; return 1; }
  jq -e '.configured == true' <<<"$body" >/dev/null ||
    { echo "重装后订阅丢了（configured=false）：$body"; return 1; }
}
