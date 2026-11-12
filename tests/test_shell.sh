#!/usr/bin/env bash
# sharealiddns shell 单元 + 压力测试（bash 运行；只依赖本机回环服务，不访问外网）
# 用法：bash tests/test_shell.sh
# 覆盖：share.lib 纯函数、sharealiddns.sh 的阿里云响应解析/转义函数、
#       check_url 的 wget 参数、get_url_cmd 的本地取数与不可达处理。

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LIB="$ROOT/myscripts/lib/share.lib"
MAIN="$ROOT/myscripts/sharealiddns/etc/init.d/sharealiddns.sh"

PASS=0
FAIL=0
FAILED_CASES=""

ok() { # ok <name>
    PASS=$((PASS + 1))
    echo "ok - $1"
}

not_ok() { # not_ok <name> <detail>
    FAIL=$((FAIL + 1))
    FAILED_CASES="$FAILED_CASES\n  - $1 ($2)"
    echo "FAIL - $1 ($2)"
}

assert_eq() { # assert_eq <name> <got> <want>
    if [ "$2" = "$3" ]; then ok "$1"; else not_ok "$1" "got=[$2] want=[$3]"; fi
}

assert_rc() { # assert_rc <name> <want_rc> <got_rc>
    if [ "$2" = "$3" ]; then ok "$1"; else not_ok "$1" "got rc=$3 want rc=$2"; fi
}

# ---- 载入 share.lib（会报固件不支持，属预期，丢弃输出）---- #
# shellcheck disable=SC1090
source "$LIB" >/dev/null 2>&1
type valid_ipv4 >/dev/null 2>&1 || { echo "FAIL - share.lib 未能载入"; exit 1; }

# ---- 从主脚本抽取纯函数（不执行主流程）---- #
# 注意：必须写临时文件再 source，直接 eval 会提前展开函数体内的 "$n" 等变量
SP="&"
_EXTRACTED="$(mktemp)"
for fn in get_Record_list get_Record_value aliddns_name_escape aliddns_name_real aliddns_response_check get_url_cmd get_ip_wget get_ip_curl isgetexternalIPV46 do_client do_remove_client get_lan_ipv46 do_aliddns_domain_Whois_Info; do
    sed -n "/^$fn()[[:space:]]*{/,/^}/p" "$MAIN" >> "$_EXTRACTED"
done
# shellcheck disable=SC1090
source "$_EXTRACTED"
rm -f "$_EXTRACTED"
type get_Record_value >/dev/null 2>&1 || { echo "FAIL - 主脚本函数抽取失败"; exit 1; }

# ================= share.lib：IP / MAC 校验 ================= #
valid_ipv4 1.2.3.4;              assert_rc "valid_ipv4 常规地址" 0 $?
valid_ipv4 0.0.0.0;              assert_rc "valid_ipv4 0.0.0.0" 0 $?
valid_ipv4 255.255.255.255;      assert_rc "valid_ipv4 广播地址" 0 $?
valid_ipv4 256.1.1.1;            assert_rc "valid_ipv4 256 越界" 1 $?
valid_ipv4 1.2.3;                assert_rc "valid_ipv4 缺一段" 1 $?
valid_ipv4 1.2.3.4.5;            assert_rc "valid_ipv4 多一段" 1 $?
valid_ipv4 "";                   assert_rc "valid_ipv4 空串" 1 $?
valid_ipv4 "abc";                assert_rc "valid_ipv4 非数字" 1 $?
valid_ipv4 01.2.3.4;             assert_rc "valid_ipv4 前导零" 1 $?
valid_ipv4 192.168.001.1;        assert_rc "valid_ipv4 001 段" 1 $?
valid_ipv4 "1.2.3.4 ";           assert_rc "valid_ipv4 尾空格" 1 $?

public_ipv4_check 8.8.8.8;       assert_rc "public_ipv4 公网" 0 $?
public_ipv4_check 172.15.0.1;    assert_rc "public_ipv4 172.15 非私网" 0 $?
public_ipv4_check 172.32.0.1;    assert_rc "public_ipv4 172.32 非私网" 0 $?
public_ipv4_check 10.0.0.1;      assert_rc "public_ipv4 10/8 私网" 1 $?
public_ipv4_check 172.16.0.1;    assert_rc "public_ipv4 172.16 私网" 1 $?
public_ipv4_check 172.31.255.255; assert_rc "public_ipv4 172.31 私网" 1 $?
public_ipv4_check 192.168.1.1;   assert_rc "public_ipv4 192.168 私网" 1 $?
public_ipv4_check 127.0.0.1;     assert_rc "public_ipv4 回环" 1 $?
public_ipv4_check 169.254.1.1;   assert_rc "public_ipv4 链路本地" 1 $?
public_ipv4_check 256.1.1.1;     assert_rc "public_ipv4 越界" 1 $?
public_ipv4_check "";            assert_rc "public_ipv4 空串" 1 $?

valid_ipv6 2001:db8::1;          assert_rc "valid_ipv6 常规" 0 $?
valid_ipv6 ::1;                  assert_rc "valid_ipv6 ::1" 0 $?
valid_ipv6 fe80::1;              assert_rc "valid_ipv6 fe80" 0 $?
valid_ipv6 gggg::1;              assert_rc "valid_ipv6 非法字符" 1 $?
valid_ipv6 "";                   assert_rc "valid_ipv6 空串" 1 $?

public_ipv6_check 2001:db8::1;   assert_rc "public_ipv6 公网" 0 $?
public_ipv6_check fe80::1;       assert_rc "public_ipv6 fe80 链路本地" 1 $?
public_ipv6_check fec0::1;       assert_rc "public_ipv6 fec0 站点本地" 1 $?
public_ipv6_check "";            assert_rc "public_ipv6 空串" 1 $?

valid_mac aa:bb:cc:dd:ee:ff;      assert_rc "valid_mac 小写" 0 $?
valid_mac AA:BB:CC:DD:EE:FF;      assert_rc "valid_mac 大写" 0 $?
valid_mac aa:bb:cc:dd:ee;         assert_rc "valid_mac 缺一段" 1 $?
valid_mac gg:bb:cc:dd:ee:ff;      assert_rc "valid_mac 非法字符" 1 $?
valid_mac "";                     assert_rc "valid_mac 空串" 1 $?

# ================= share.lib：数值 / 字符串 ================= #
check_number 0;                  assert_rc "check_number 0" 0 $?
check_number 123;                assert_rc "check_number 123" 0 $?
check_number 12a;                assert_rc "check_number 12a" 1 $?
check_number "";                 assert_rc "check_number 空串" 1 $?
check_number -1;                 assert_rc "check_number -1" 1 $?

iseq 1 1;                        assert_rc "iseq 相等数字" 0 $?
iseq 1 2;                        assert_rc "iseq 不等数字" 1 $?
iseq a a;                        assert_rc "iseq 相等字符串" 0 $?
iseq a b;                        assert_rc "iseq 不等字符串" 1 $?
isge 5 5;                        assert_rc "isge 等于" 0 $?
isge 6 5;                        assert_rc "isge 大于" 0 $?
isge 4 5;                        assert_rc "isge 小于" 1 $?
isgt 6 5;                        assert_rc "isgt 大于" 0 $?
isgt 5 5;                        assert_rc "isgt 等于" 1 $?
isle 5 5;                        assert_rc "isle 等于" 0 $?
islt 4 5;                        assert_rc "islt 小于" 0 $?
islt 5 5;                        assert_rc "islt 等于" 1 $?
isEmpty "";                      assert_rc "isEmpty 空串" 0 $?
isEmpty x;                       assert_rc "isEmpty 非空" 1 $?
isNotEmpty x;                    assert_rc "isNotEmpty 非空" 0 $?
isNotEmpty "";                   assert_rc "isNotEmpty 空串" 1 $?
assert_eq "sadd 1+2" "$(sadd 1 2)" "3"
assert_eq "sdec 5-2" "$(sdec 5 2)" "3"
assert_eq "math 2*3+1" "$(math '2*3+1')" "7"
assert_eq "STRLSP 常规截取" "$(STRLSP "hello" 1 3)" "ell"
assert_eq "STRLSP 非数字起始位被拒" "$(STRLSP "hello" "x" 2)" ""
assert_eq "STRLSP 非数字长度被拒" "$(STRLSP "hello" 1 "y")" ""
assert_eq "STRLSP 空串" "$(STRLSP "" 1 2)" ""

# ================= share.lib：URL 编码 ================= #
assert_eq "urlencode 保留字符" "$(do_urlencode "abc-._~")" "abc-._~"
assert_eq "urlencode 空格" "$(do_urlencode "a b")" "a%20b"
assert_eq "urlencode 制表符" "$(do_urlencode "$(printf 'a\tb')")" "a%09b"
assert_eq "urlencode & 与 =" "$(do_urlencode "a&b=c")" "a%26b%3Dc"
assert_eq "urlencode / 与 :" "$(do_urlencode "a/b:c")" "a%2Fb%3Ac"
assert_eq "urlencode 空串" "$(do_urlencode "")" ""
assert_eq "urlencode 时间戳" "$(do_urlencode "2015-01-09T12:00:00Z")" "2015-01-09T12%3A00%3A00Z"

printf 'abc.com' | domainencode >/dev/null 2>&1
assert_rc "domainencode 合法域名" 0 $?
printf 'a_b.com' | domainencode >/dev/null 2>&1
assert_rc "domainencode 下划线非法" 1 $?
printf 'a-b.com' | domainencode >/dev/null 2>&1
assert_rc "domainencode 连字符合法" 0 $?

# ================= 主脚本：阿里云响应解析 ================= #
RESP='{"PageNumber":1,"PageSize":1,"TotalCount":2,"DomainRecords":{"Record":[{"RecordId":"123","RR":"www","Type":"A","Value":"1.2.3.4","TTL":600,"Status":"Enable","Locked":false,"Line":"default","DomainName":"example.com"},{"RecordId":"456","RR":"www","Type":"A","Value":"5.6.7.8","TTL":600,"Status":"Enable","Locked":false,"Line":"default","DomainName":"example.com"}]},"RequestId":"req-1"}'
# RequestId 是响应最后一个字段，旧版会带出尾部 "}"（req-1}）；现已剥掉，按精确值断言
assert_eq "get_Record_value RequestId 去尾部}" "$(get_Record_value "$RESP" "RequestId")" "req-1"
assert_eq "get_Record_value RR 通配符 *" "$(get_Record_value '"RR":"*","Value":"1.2.3.4"' "RR")" "*"

assert_eq "get_Record_value TotalCount" "$(get_Record_value "$RESP" "TotalCount")" "2"
assert_eq "get_Record_value 不存在的键" "$(get_Record_value "$RESP" "NoSuchKey")" ""
assert_eq "get_Record_value 空响应" "$(get_Record_value "" "RequestId")" ""
assert_eq "get_Record_value 错误响应" "$(get_Record_value '{"Code":"InvalidDomain","Message":"bad"}' "RequestId")" ""

REC1="$(get_Record_list "$RESP" 1)"
REC2="$(get_Record_list "$RESP" 2)"
assert_eq "get_Record_list 第1条 RecordId" "$(get_Record_value "$REC1" "RecordId")" "123"
assert_eq "get_Record_list 第1条 Value" "$(get_Record_value "$REC1" "Value")" "1.2.3.4"
assert_eq "get_Record_list 第1条 RR" "$(get_Record_value "$REC1" "RR")" "www"
assert_eq "get_Record_list 第2条 RecordId" "$(get_Record_value "$REC2" "RecordId")" "456"
assert_eq "get_Record_list 第2条 Value" "$(get_Record_value "$REC2" "Value")" "5.6.7.8"
assert_eq "get_Record_list 越界" "$(get_Record_list "$RESP" 9)" ""

assert_eq "aliddns_name_escape @" "$(aliddns_name_escape "@")" "%40"
assert_eq "aliddns_name_escape *" "$(aliddns_name_escape "*")" "%2A"
assert_eq "aliddns_name_escape www" "$(aliddns_name_escape "www")" "www"
assert_eq "aliddns_name_real @" "$(aliddns_name_real "@" "example.com")" "example.com"
assert_eq "aliddns_name_real 空" "$(aliddns_name_real "" "example.com")" "example.com"
assert_eq "aliddns_name_real www" "$(aliddns_name_real "www" "example.com")" "www.example.com"

aliddns_response_check "";                                  assert_rc "response_check 空响应" 1 $?
aliddns_response_check '{"RequestId":"x"}';                  assert_rc "response_check 正常响应" 0 $?
aliddns_response_check '{"Message":"see https://error-center.aliyun.com/x"}'; assert_rc "response_check 错误中心" 1 $?
aliddns_response_check '{"Code":"Throttling","Message":"denied","RequestId":"x"}'; assert_rc "response_check 限流错误" 1 $?
aliddns_response_check '{"Code":"InvalidAccessKeyId.NotFound","Message":"bad key","RequestId":"x"}'; assert_rc "response_check 密钥错误" 1 $?
aliddns_response_check '{"Code" : "Throttling","Message":"denied","RequestId":"x"}'; assert_rc "response_check 限流错误（冒号前空格）" 1 $?
aliddns_response_check '{"TotalCount":1,"DomainRecords":{"Record":[{"DomainName":"code.example.com","RR":"www"}]},"RequestId":"x"}'; assert_rc "response_check 域名含 code 不误判" 0 $?
aliddns_response_check '<html><body>502 Bad Gateway</body></html>'; assert_rc "response_check HTML 错误页" 1 $?
aliddns_response_check '{"TotalCount":1,"DomainRecords":{"Record":[]}}'; assert_rc "response_check 无 RequestId" 1 $?
aliddns_response_check '{"RequestId":"x","TotalCount":0}'; assert_rc "response_check 成功无记录" 0 $?
aliddns_response_check '{"Code":"Throttling","Message":"denied","RequestId":"x"}'; assert_rc "response_check 限流错误（含 RequestId）" 1 $?

# ================= share.lib：check_url 参数（用假 wget 捕获实参） ================= #
OLD_PATH="$PATH"
FAKEBIN="$(mktemp -d)"
cat > "$FAKEBIN/wget" <<'EOF'
#!/bin/sh
echo "$@" >> "$FAKE_WGET_ARGS"
echo "HTTP/1.1 200 OK"
EOF
chmod +x "$FAKEBIN/wget"
export FAKE_WGET_ARGS="$FAKEBIN/args.log"
PATH="$FAKEBIN:$PATH"
check_url "http://127.0.0.1:9/" 2 1
assert_rc "check_url 假 wget 返回 200" 0 $?
ARGS_CAPTURED="$(cat "$FAKEBIN/args.log")"
echo "$ARGS_CAPTURED" | grep -q -- "--spider" && ok "check_url 带 --spider" || not_ok "check_url 带 --spider" "args=[$ARGS_CAPTURED]"
echo "$ARGS_CAPTURED" | grep -q -- "-T 2" && ok "check_url 带 -T 超时" || not_ok "check_url 带 -T 超时" "args=[$ARGS_CAPTURED]"
echo "$ARGS_CAPTURED" | grep -q -- "-t 1" && ok "check_url 带 -t 重试" || not_ok "check_url 带 -t 重试" "args=[$ARGS_CAPTURED]"
echo "$ARGS_CAPTURED" | grep -q "no-check-certificate" && not_ok "check_url 不应关闭证书校验" "args=[$ARGS_CAPTURED]" || ok "check_url 不应关闭证书校验"
echo "$ARGS_CAPTURED" | grep -qE '(^| )T( |$)' && not_ok "check_url 不应有裸 T 参数" "args=[$ARGS_CAPTURED]" || ok "check_url 不应有裸 T 参数"
PATH="$OLD_PATH"
rm -rf "$FAKEBIN"

# ================= get_url_cmd：本地取数 + 不可达 ================= #
WGET="$(command -v wget)"
CURL="$(command -v curl)"
HTTP_ROOT="$(mktemp -d)"
printf '203.0.113.7' > "$HTTP_ROOT/ip.txt"
PORT=$((18000 + $$ % 1000))
python3 -m http.server "$PORT" --bind 127.0.0.1 --directory "$HTTP_ROOT" >/dev/null 2>&1 &
HTTP_PID=$!
sleep 1
assert_eq "get_url_cmd wget 取本地 IP" "$(get_url_cmd "http://127.0.0.1:$PORT/ip.txt" 3 ipv4 wget)" "203.0.113.7"
assert_eq "get_url_cmd curl 取本地 IP" "$(get_url_cmd "http://127.0.0.1:$PORT/ip.txt" 3 ipv4 curl)" "203.0.113.7"
assert_eq "get_url_cmd 默认工具取本地 IP" "$(get_url_cmd "http://127.0.0.1:$PORT/ip.txt" 3 ipv4)" "203.0.113.7"
kill "$HTTP_PID" 2>/dev/null
wait "$HTTP_PID" 2>/dev/null
rm -rf "$HTTP_ROOT"
# 目标端口无服务：应快速返回空串，不挂住
T0=$(date +%s)
EMPTY_OUT="$(get_url_cmd "http://127.0.0.1:$PORT/ip.txt" 2 ipv4)"
ELAPSED=$(( $(date +%s) - T0 ))
assert_eq "get_url_cmd 不可达返回空" "$EMPTY_OUT" ""
if [ "$ELAPSED" -le 10 ]; then ok "get_url_cmd 不可达不超时挂起 (${ELAPSED}s)"; else not_ok "get_url_cmd 不可达不超时挂起" "elapsed=${ELAPSED}s"; fi

# ================= 主脚本：do_aliddns_domain_Whois_Info 状态匹配 ================= #
# 用桩替换 API 调用，只测状态码匹配逻辑
aliddns_domain_Whois_Info() { printf '%s' "$WHOIS_STUB_JSON"; }
WHOIS_STUB_JSON='{"RequestId":"x","StatusList":{"Status":["clientHold","redemptionPeriod"]}}'
do_aliddns_domain_Whois_Info "example.com" >/dev/null 2>&1
assert_rc "whois 含 clientHold/redemptionPeriod 判异常" 1 $?
[ "$isdnsWhois" = "0" ] && ok "whois 异常 isdnsWhois=0" || not_ok "whois 异常 isdnsWhois=0" "got=[$isdnsWhois]"
WHOIS_STUB_JSON='{"RequestId":"x","StatusList":{"Status":["clientDeleteProhibited","ok"]}}'
do_aliddns_domain_Whois_Info "example.com" >/dev/null 2>&1
assert_rc "whois 仅禁止类状态判健康" 0 $?
[ "$isdnsWhois" = "1" ] && ok "whois 健康 isdnsWhois=1" || not_ok "whois 健康 isdnsWhois=1" "got=[$isdnsWhois]"

# ================= 假工具箱：wget/curl/ip/sleep/logger ================= #
# 下面几节共用：假 wget/curl 只记录实参并回固定 IP；假 ip 回固定邻居表；
# 假 sleep 立即返回（do_client 是无限循环，靠 timeout 截断）；假 logger 防写 syslog 挂住
FAKEBIN2="$(mktemp -d)"
cat > "$FAKEBIN2/wget" <<'EOF'
#!/bin/sh
echo "$@" >> "$FAKE_TOOL_ARGS"
printf '203.0.113.7'
EOF
cat > "$FAKEBIN2/curl" <<'EOF'
#!/bin/sh
echo "$@" >> "$FAKE_TOOL_ARGS"
printf '203.0.113.7'
EOF
cat > "$FAKEBIN2/ip" <<'EOF'
#!/bin/sh
if [ "$1" = "-4" ]; then
    echo "192.168.1.5 dev eth0 lladdr aa:bb:cc:dd:ee:ff REACHABLE"
else
    echo "2001:db8::5 dev eth0 lladdr aa:bb:cc:dd:ee:ff REACHABLE"
fi
EOF
cat > "$FAKEBIN2/sleep" <<'EOF'
#!/bin/sh
exit 0
EOF
cat > "$FAKEBIN2/logger" <<'EOF'
#!/bin/sh
exit 0
EOF
chmod +x "$FAKEBIN2/wget" "$FAKEBIN2/curl" "$FAKEBIN2/ip" "$FAKEBIN2/sleep" "$FAKEBIN2/logger"
export FAKE_TOOL_ARGS="$FAKEBIN2/args.log"
OLD_PATH2="$PATH"
OLD_WGET="$WGET"; OLD_CURL="$CURL"
PATH="$FAKEBIN2:$PATH"
WGET="$FAKEBIN2/wget"; CURL="$FAKEBIN2/curl"

# ---- get_url_cmd / get_ip_wget / get_ip_curl：超时与重试参数 ---- #
: > "$FAKE_TOOL_ARGS"
assert_eq "get_url_cmd wget 取数" "$(get_url_cmd "http://127.0.0.1/ip.txt" 3 ipv4 wget)" "203.0.113.7"
grep -q -- "-t 1" "$FAKE_TOOL_ARGS" && ok "get_url_cmd wget 只试 1 次" || not_ok "get_url_cmd wget 只试 1 次" "args=[$(cat "$FAKE_TOOL_ARGS")]"
: > "$FAKE_TOOL_ARGS"
assert_eq "get_url_cmd curl 取数" "$(get_url_cmd "http://127.0.0.1/ip.txt" 3 ipv4 curl)" "203.0.113.7"
grep -q -- "--max-time 9" "$FAKE_TOOL_ARGS" && ok "get_url_cmd curl 总超时 9s" || not_ok "get_url_cmd curl 总超时 9s" "args=[$(cat "$FAKE_TOOL_ARGS")]"
: > "$FAKE_TOOL_ARGS"
assert_eq "get_ip_wget 取数" "$(get_ip_wget "http://127.0.0.1/ip.txt" 3 ipv4)" "203.0.113.7"
grep -q -- "-t 1" "$FAKE_TOOL_ARGS" && ok "get_ip_wget 只试 1 次" || not_ok "get_ip_wget 只试 1 次" "args=[$(cat "$FAKE_TOOL_ARGS")]"
: > "$FAKE_TOOL_ARGS"
assert_eq "get_ip_curl 取数" "$(get_ip_curl "http://127.0.0.1/ip.txt" 3 ipv4)" "203.0.113.7"
grep -q -- "--max-time 9" "$FAKE_TOOL_ARGS" && ok "get_ip_curl 总超时 9s" || not_ok "get_ip_curl 总超时 9s" "args=[$(cat "$FAKE_TOOL_ARGS")]"

# ---- isgetexternalIPV46：现探测，不写缓存 ---- #
rm -f /tmp/isgetexternalIPV4.success /tmp/isgetexternalIPV6.success
isgetexternalIPV46 ipv4; assert_rc "isgetexternalIPV46 有响应" 0 $?
[ ! -e /tmp/isgetexternalIPV4.success ] && ok "isgetexternalIPV46 不写缓存文件" || not_ok "isgetexternalIPV46 不写缓存文件" "cache file exists"
WGET=""
isgetexternalIPV46 ipv4; assert_rc "isgetexternalIPV46 无 wget 返回 1" 1 $?
cat > "$FAKEBIN2/wget-empty" <<'EOF'
#!/bin/sh
exit 0
EOF
chmod +x "$FAKEBIN2/wget-empty"
WGET="$FAKEBIN2/wget-empty"
isgetexternalIPV46 ipv4; assert_rc "isgetexternalIPV46 空响应返回 1" 1 $?
WGET="$FAKEBIN2/wget"
isgetexternalIPV46 bogus; assert_rc "isgetexternalIPV46 非法类型返回 1" 1 $?

# ---- get_lan_ipv46：日志里的 MAC 取第 5 列 ---- #
OLD_IP2="$IP2"; IP2="$FAKEBIN2/ip"
LAN_OUT="$(mktemp)"
get_lan_ipv46 "AA:BB:CC:DD:EE:FF" "eth0" > "$LAN_OUT" 2>&1
assert_rc "get_lan_ipv46 找到内外网 IP" 0 $?
assert_eq "get_lan_ipv46 lan_ipv6_IP" "$lan_ipv6_IP" "2001:db8::5"
grep -q -- "-\[aa:bb:cc:dd:ee:ff\]" "$LAN_OUT" && ok "get_lan_ipv46 日志 MAC 不是 lladdr" || not_ok "get_lan_ipv46 日志 MAC 不是 lladdr" "out=[$(cat "$LAN_OUT")]"
IP2="$OLD_IP2"

# ---- do_client：邻居 MAC 取第 5 列，状态取第 6 列 ---- #
OLD_ETH="$ETH"; ETH="eth0"; export ETH
export -f do_client logs isEmpty iseq isNumber sadd set_lowercase
CLIENT_OUT="$(mktemp)"
timeout 3 bash -c 'do_client client ipv4' > "$CLIENT_OUT" 2>&1
grep -q "aa:bb:cc:dd:ee:ff" "$CLIENT_OUT" && ok "do_client 日志含真实 MAC" || not_ok "do_client 日志含真实 MAC" "out=[$(head -c 500 "$CLIENT_OUT")]"
grep -q "可达邻居" "$CLIENT_OUT" && ok "do_client REACHABLE 判可达" || not_ok "do_client REACHABLE 判可达" "out=[$(head -c 500 "$CLIENT_OUT")]"
grep -q "消失邻居" "$CLIENT_OUT" && not_ok "do_client 不应判消失" "out=[$(head -c 500 "$CLIENT_OUT")]" || ok "do_client 不应判消失"
ETH="$OLD_ETH"

# ---- do_remove_client：按首行 MAC 删除，删完退出 ---- #
FAKE_IP_STATE="$(mktemp)"
printf '2001:db8::5 dev eth0 lladdr aa:bb:cc:dd:ee:ff REACHABLE\n' > "$FAKE_IP_STATE"
export FAKE_IP_STATE
cat > "$FAKEBIN2/ip" <<'EOF'
#!/bin/sh
if [ "$3" = "del" ]; then
    case "$6" in
        ??:??:??:??:??:??) : > "$FAKE_IP_STATE"; exit 0;;
        *) exit 1;;
    esac
else
    cat "$FAKE_IP_STATE" 2>/dev/null
fi
EOF
chmod +x "$FAKEBIN2/ip"
export -f do_remove_client logs isEmpty isNotEmpty
RM_OUT="$(mktemp)"
timeout 5 bash -c 'do_remove_client' > "$RM_OUT" 2>&1
assert_rc "do_remove_client 删完退出" 0 $?

# ---- 恢复环境 ---- #
PATH="$OLD_PATH2"
WGET="$OLD_WGET"; CURL="$OLD_CURL"
rm -rf "$FAKEBIN2" "$FAKE_IP_STATE" "$CLIENT_OUT" "$RM_OUT" "$LAN_OUT"

# ================= 汇总 ================= #
echo "----------------------------------------"
echo "PASS=$PASS FAIL=$FAIL"
if [ -n "$FAILED_CASES" ]; then printf '失败用例:%b\n' "$FAILED_CASES"; fi
[ "$FAIL" -eq 0 ]
