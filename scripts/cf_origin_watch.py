#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
cf_origin_watch.py —— Cloudflare 52x + 源站裸 IP 双路监控

为什么要两路：522 是 CF 侧事件，源站 nginx 完全看不到日志。
单看 CF 不知道是 CDN 的锅还是链路的锅，单看探针不知道用户到底受没受影响。
两路交叉才能直接判因：

    探针正常 + CF 52x  ->  CF 回源路径问题      找 Cloudflare
    探针挂   + CF 52x  ->  源站链路问题        找机房
    探针挂   + 无 52x  ->  探针自身网络问题    忽略

用法:
    cf_origin_watch.py                 前台运行(systemd 用)
    cf_origin_watch.py --once          跑一轮就退出(测试用)
    cf_origin_watch.py --report [分钟] 打印最近 N 分钟时间线(默认 60)
    cf_origin_watch.py --test-tg       发一条 Telegram 测试消息
    cf_origin_watch.py --mtr <名字>    立刻抓一份路由快照并推送
    cf_origin_watch.py --baseline      刷新全部正常路由基线
    cf_origin_watch.py --chats         列出 bot 能看到的群/会话 id(配运营群用)
    cf_origin_watch.py --announce-preview  预览接入说明文案(不发送)
    cf_origin_watch.py --announce-reset    清除已发送记录,下轮重新发一遍
    cf_origin_watch.py --pending       列出等待自动撤回的运营群消息
    cf_origin_watch.py --sweep         立刻撤回已到期的运营群消息
    cf_origin_watch.py --zones-preview 按 zones_auto 规则算一遍各服务器的轮询范围并与配置对比(只读)
    cf_origin_watch.py --peek <名字>   本节点对某台的即时视角(TCP/HTTPS/目标机自检), 输出 JSON
    cf_origin_watch.py --peek-forced   同上, 但目标名从 SSH_ORIGINAL_COMMAND 取("peek <名字>"),
                                       给对端节点 authorized_keys 的 command= 用, 只认这一种命令

推运营群前的第二票(2026-09-14 起):
    单节点永远分不清"对面挂了"和"我到对面的路挂了"。09-14 mru 自己的上联抖了 17 分钟,
    应用层检查把美国 6 台全判成"页面报错", 往 7 个运营群推了 20 条异常 + 20 条恢复;
    同期 dev 零事件、CF 零 52x、源站 nginx 没断流。所以现在任何一条运营群播报都要先
    过 confirm_outage(): 本节点黑匣子 -> 对端观测点(peers) -> 目标机自检 -> CF 52x。
    配置: "peers": [{"name": "dev", "ssh": "ssh -p 22351 -i ... root@1.2.3.4"}]
          origins[].ssh = 本节点能 ssh 到该机的别名(有则做目标机自检)
"""
import json, os, socket, ssl, subprocess, sys, time, datetime, threading, urllib.request, urllib.parse, urllib.error, glob

CONF_PATH = "/opt/site_manager/config/monitor_cf.json"
GRAPHQL = "https://api.cloudflare.com/client/v4/graphql"
UA = "site-manager-cf-watch/1.0"

# 需要判定为"源站不可达"的 CF 状态码。52x 全家桶:
#   520 未知错误 521 源站拒绝 522 连接超时 523 源站不可达 524 超时
#   525 SSL握手失败 526 源站证书无效 527 Railgun
ORIGIN_ERR_CODES = [520, 521, 522, 523, 524, 525, 526, 527]


def now_utc():
    return datetime.datetime.now(datetime.timezone.utc)


def log_line(cfg, obj):
    obj["ts"] = now_utc().strftime("%Y-%m-%dT%H:%M:%SZ")
    path = cfg["log"]
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "a") as f:
        f.write(json.dumps(obj, ensure_ascii=False) + "\n")


def prune_log(cfg):
    """按保留天数裁掉老行。文件不大(每分钟几行), 整体重写最简单可靠。"""
    path = cfg["log"]
    if not os.path.exists(path):
        return
    cutoff = (now_utc() - datetime.timedelta(days=cfg.get("retain_days", 30))).strftime("%Y-%m-%dT%H:%M:%SZ")
    keep = []
    with open(path) as f:
        for line in f:
            if line[:1] != "{":
                continue
            try:
                if json.loads(line).get("ts", "") >= cutoff:
                    keep.append(line)
            except Exception:
                pass
    with open(path + ".tmp", "w") as f:
        f.writelines(keep)
    os.replace(path + ".tmp", path)


# ---------------------------------------------------------------- Telegram

def tg_api(token, method, **params):
    """调一次 Bot API。返回 (result 或 None, 错误原因或 None)。

    错误原因尽量用 Telegram 自己的 description("Bad Request: chat not found",
    "Forbidden: bot was kicked from the group chat"...), 网络异常才退回 Python 的报错。
    群升级成超级群后 id 会变, Telegram 在 parameters.migrate_to_chat_id 里给新 id,
    一并拼进原因 —— 这是运营群"突然发不出去"最常见的原因之一。
    """
    data = urllib.parse.urlencode({k: str(v) for k, v in params.items()}).encode()
    req = urllib.request.Request(f"https://api.telegram.org/bot{token}/{method}",
                                 data=data, headers={"User-Agent": UA})
    try:
        with urllib.request.urlopen(req, timeout=15) as r:
            body = json.load(r)
    except urllib.error.HTTPError as ex:
        try:
            body = json.load(ex)
        except Exception:
            return None, f"HTTP {ex.code}"
    except Exception as ex:
        return None, str(ex)[:200]
    if body.get("ok"):
        return body.get("result", True), None
    err = body.get("description") or f"HTTP {body.get('error_code')}"
    mig = (body.get("parameters") or {}).get("migrate_to_chat_id")
    if mig:
        err += f" (群已升级, 新 chat_id={mig})"
    return None, err


def tg_send(cfg, text):
    if cfg.get("alert") is False:      # 静默观测点
        return False, "本节点仅记录不告警"
    tg = cfg.get("telegram") or {}
    chat_id = tg.get("chat_id")
    tok_file = tg.get("token_file")
    if not chat_id or not tok_file or not os.path.exists(tok_file):
        return False, "telegram 未配置(缺 chat_id 或 token)"
    token = open(tok_file).read().strip()
    result, err = tg_api(token, "sendMessage", chat_id=chat_id, text=text,
                         parse_mode="HTML", disable_web_page_preview="true")
    if err:
        # 管理员通道发不出去只能记日志 —— 这已经是最后一条通道了
        log_line(cfg, {"ev": "tg_fail", "target": "admin", "chat": str(chat_id), "err": err})
        return False, err
    log_sent(cfg, chat_id, result, text, "管理员告警")
    # 私聊也定期清理(10-07 起): 告警全在 jsonl 里, 私聊只看最近的
    remember_ephemeral(cfg, chat_id, (result or {}).get("message_id"),
                       ttl=cfg.get("admin_msg_ttl_sec", 0), kind="admin")
    return True, "ok"


def log_sent(cfg, chat_id, result, text, ctx):
    """每条发出去的消息都记下 message_id —— 发错了/要撤回时凭它 deleteMessage。
    (10-06 dev 补发的 IMDB 接入说明没记 id, 只能逐个探测 message_id 才找到。)
    查: grep '"ev": "tg_sent"' <log> ; 撤回: tg-send <chat> --delete <mid>"""
    log_line(cfg, {"ev": "tg_sent", "ctx": ctx, "chat": str(chat_id),
                   "mid": (result or {}).get("message_id") if isinstance(result, dict) else None,
                   "text": " ".join(str(text).split())[:80]})


# --------------------------------------------------------------- 运营通知

# 技术告警(给运维)和业务通知(给运营)是两回事:
#   - 运维要判因数据:IP、路由、丢包、内核计数器
#   - 运营只要知道"哪个站、什么时候挂的、什么时候好的",不需要也不该看到 IP
# 所以这里单独走一套:按业务别名 + 一个后台域名,推到各自的运营群。
# 一台服务器可以承载多个业务 -> 一个 origin 可以对应多条 notify,分别推不同的群。

# 这些错误不是网络抖动, 重试一万次也不会好 —— 群解散了 / bot 被踢了 / 群升级换了 id。
# 碰到就得让管理员知道, 否则运营群可以一直静默失败下去(09-02 UNI151 就是这样,
# 旧群 id 失效了日志里只有一个 ok:false, 谁也没注意)。
PERMANENT_ERRS = ("chat not found", "bot was kicked", "bot was blocked", "group chat was upgraded",
                  "not a member", "have no rights", "chat_id is empty", "user is deactivated",
                  "group chat was deactivated", "bot is not a member")
_chat_fail_told = {}        # chat_id -> 上次提醒管理员的时间, 每个群每天最多提醒一次


def _tell_admin_chat_dead(cfg, chat_id, err, ctx):
    if not any(k in err.lower() for k in PERMANENT_ERRS):
        return
    now = time.time()
    if now - _chat_fail_told.get(str(chat_id), 0) < 86400:
        return
    _chat_fail_told[str(chat_id)] = now
    alias = next((n.get("alias") for n in (cfg.get("notify") or [])
                  if str(chat_id) in [str(c) for c in (n.get("chats") or [])]), "?")
    tg_send(cfg, f"⚠️ <b>运营群推送失败</b> — {alias}\n"
                 f"chat_id: <code>{chat_id}</code>\n"
                 f"场景: {ctx}\n"
                 f"原因: {err}\n\n"
                 f"这类错误不会自愈, 请检查群是否解散/换群/bot 被踢, "
                 f"然后更新 monitor_cf.json 的 notify[].chats 并重启。")


def tg_send_chat(cfg, chat_id, text, ephemeral=False, ctx="运营通知"):
    """往运营群发一条。返回 (ok, 失败原因)。

    ephemeral=True: 记下 message_id, 满 ops_msg_ttl_sec 后由 sweep_ephemeral 撤回。
    """
    if cfg.get("alert") is False:          # 静默观测点不发任何消息
        return False, "本节点静默"
    # ops_notify:false = 本节点只给管理员发技术告警, 不碰运营群。
    # 用于第二观测点: 它要能在主节点挂掉时顶上报警, 但不能让运营群收到重复播报。
    if cfg.get("ops_notify", True) is False:
        return False, "本节点 ops_notify:false"
    tok_file = (cfg.get("telegram") or {}).get("token_file")
    if not chat_id or not tok_file or not os.path.exists(tok_file):
        return False, "未配置 chat_id 或 token"
    token = open(tok_file).read().strip()
    result, err = tg_api(token, "sendMessage", chat_id=chat_id, text=text,
                         parse_mode="HTML", disable_web_page_preview="true")
    if err:
        _tell_admin_chat_dead(cfg, chat_id, err, ctx)
        return False, err
    log_sent(cfg, chat_id, result, text, ctx)
    if ephemeral:
        remember_ephemeral(cfg, chat_id, (result or {}).get("message_id"))
    return True, None


# ------------------------------------------------- 运营群消息定时撤回
# 群里堆着几小时前的"服务异常"会让人以为现在还在出问题(新入群的尤其), 而排障要的
# 历史全在 jsonl 里, 群消息本身没有留存价值 —— 所以业务播报发出去就登记, 到期由
# bot 自己撤回。每群一次的接入说明不在此列。
# 管理员私聊的技术告警 10-07 起也进队列, 用单独的 admin_msg_ttl_sec(默认 0 = 不撤),
# 每条自带 ttl; Telegram 只许撤 48 小时内的, 所以它不能超过 DELETE_MAX_AGE。
#
# 队列落盘, 进程重启不丢。删不掉的两种情况分开处理: Telegram 明确报错(消息已被人
# 手工删掉/找不到)直接出队, 网络问题则留着下轮重试。
PENDING_DEL = "/opt/site_manager/config/.pending_del.json"
DELETE_MAX_AGE = 47 * 3600     # Telegram 只允许撤回 48 小时内的消息, 留 1 小时余量


def _load_pending():
    try:
        return json.load(open(PENDING_DEL))
    except Exception:
        return []


def _save_pending(items):
    try:
        with open(PENDING_DEL, "w") as f:
            json.dump(items, f)
        os.chmod(PENDING_DEL, 0o600)
    except Exception:
        pass


def remember_ephemeral(cfg, chat_id, message_id, ttl=None, kind="ops"):
    if ttl is None:
        ttl = cfg.get("ops_msg_ttl_sec", 3600)
    if not ttl or not message_id:
        return
    items = _load_pending()
    items.append({"chat": str(chat_id), "mid": int(message_id), "sent": time.time(),
                  "ttl": min(int(ttl), DELETE_MAX_AGE), "kind": kind})
    _save_pending(items)


def _item_ttl(cfg, it):
    """旧队列里的条目没有 ttl 字段, 一律是运营群消息"""
    return it["ttl"] if "ttl" in it else cfg.get("ops_msg_ttl_sec", 3600)


def tg_delete(token, chat_id, message_id):
    """返回 (成功?, 不可重试的原因)。原因为 None = 网络问题, 值得下轮重试。"""
    result, err = tg_api(token, "deleteMessage", chat_id=chat_id, message_id=message_id)
    if not err:
        return True, None
    # Telegram 明确拒绝(Bad Request/Forbidden)= 不可重试; 限流和网络问题 = 下轮再来
    if err.startswith(("Bad Request", "Forbidden")):
        return False, err
    return False, None


def sweep_ephemeral(cfg):
    items = _load_pending()
    # 某类功能关掉了(ttl 配成 0), 顺手把这类残留丢掉
    live = [it for it in items
            if (cfg.get("admin_msg_ttl_sec", 0) if it.get("kind") == "admin"
                else cfg.get("ops_msg_ttl_sec", 3600))]
    if len(live) != len(items):
        _save_pending(live)
        items = live
    tok_file = (cfg.get("telegram") or {}).get("token_file")
    if not items or not tok_file or not os.path.exists(tok_file):
        return
    token = open(tok_file).read().strip()
    now, keep = time.time(), []
    for it in items:
        age = now - it.get("sent", 0)
        if age < _item_ttl(cfg, it):
            keep.append(it)
            continue
        ok, err = tg_delete(token, it["chat"], it["mid"])
        if not ok and err is None:
            if age < DELETE_MAX_AGE:
                keep.append(it)             # 网络问题, 下轮重试
                continue
            err = "超过 48 小时, Telegram 不再允许撤回"
        log_line(cfg, {"ev": "ops_del", "chat": it["chat"], "mid": it["mid"],
                       "kind": it.get("kind", "ops"), "ok": ok, "err": err})
    if len(keep) != len(items):
        _save_pending(keep)


def local_time(tz_offset):
    """按各运营所在时区显示,省得他们自己换算"""
    t = now_utc() + datetime.timedelta(hours=tz_offset)
    return t.strftime("%m-%d %H:%M")


def fmt_duration(sec):
    return f"{int(sec or 0)} 秒"


# CF 给代理域名自动开了一批非标端口(2052/2053/2082/2083/2086/2087/8080/8443),
# 而机队所有源站只监听 80/443 —— 扫描器随手打一个非标端口就必然 522,
# 跟源站健康毫无关系。这类 522 照常记账, 但不计入告警阈值, 否则天天假警。
STD_PORTS = {"80", "443"}


def is_port_noise(cfg, host):
    """host 带非标端口 = 扫描器噪音。配 ignore_nonstandard_ports:false 可关掉"""
    if cfg.get("ignore_nonstandard_ports", True) is False:
        return False
    if ":" not in host:
        return False
    return host.rsplit(":", 1)[1] not in STD_PORTS


def notify_ops(cfg, origin_name, event, down_sec=None, only_chats=None):
    """给该服务器上所有业务的运营群推消息。event: 'down' | 'app_down' | 'up'

    返回真正送达的 chat 集合。恢复通知要靠它配对 —— 2026-09-01 gmg2 自己断网时
    异常通知发送失败(连不上 Telegram), 恢复时网络回来了却发成功了, 运营群收到一条
    没头没尾的"✅ 服务已恢复 273 秒"。所以恢复只发给当初真正收到过异常通知的群。
    """
    delivered = set()
    for n in (cfg.get("notify") or []):
        if n.get("origin") != origin_name or not n.get("chats"):
            continue
        tz = n.get("tz", 8)
        tzname = n.get("tz_name", f"UTC{tz:+d}")
        alias = n.get("alias", origin_name)
        domain = n.get("domain", "")
        if event == "down":
            msg = (f"⚠️ <b>服务异常</b>\n\n"
                   f"站点：{alias}\n"
                   + (f"地址：{domain}\n" if domain else "")
                   + f"时间：{local_time(tz)}（{tzname}）\n\n"
                     f"522 错误，通常 5 分钟内恢复。")
        elif event == "app_down":
            msg = (f"⚠️ <b>服务异常</b>\n\n"
                   f"站点：{alias}\n"
                   + (f"地址：{domain}\n" if domain else "")
                   + f"时间：{local_time(tz)}（{tzname}）\n\n"
                     f"页面报错（502/504），已通知技术处理。")
        else:
            msg = (f"✅ <b>服务已恢复</b>\n\n"
                   f"站点：{alias}\n"
                   + (f"地址：{domain}\n" if domain else "")
                   + f"时间：{local_time(tz)}（{tzname}）\n"
                     f"中断：{fmt_duration(down_sec)}")
        for chat in n["chats"]:
            if only_chats is not None and chat not in only_chats:
                continue               # 当初没收到异常通知的群, 不发恢复
            ok, err = tg_send_chat(cfg, chat, msg, ephemeral=True,
                                   ctx=f"{alias} {'恢复' if event == 'up' else '异常'}通知")
            if ok:
                delivered.add(chat)
            log_line(cfg, {"ev": "ops_notify", "origin": origin_name, "alias": alias,
                           "event": event, "chat": str(chat), "ok": ok, "err": err})
    return delivered


# 接入说明:每个群只发一次。bot 尚未获批入群的会发送失败,
# 状态文件里就不记录,下个周期自动重试 —— 所以入群批准后会自动补发,无需人工干预。

ANNOUNCE_STATE = "/opt/site_manager/config/.announced.json"

ANNOUNCE_TPL = """🤖 <b>服务监控已接入</b>

本群自动播报 <b>{alias}</b>（{domain}）的服务状态。

⚠️ 服务异常 —— 站点无法访问时通知
✅ 服务已恢复 —— 附中断时长

522 错误，通常 5 分钟内恢复。
时间按{tz_name}时间显示。"""


def _announced():
    try:
        return set(json.load(open(ANNOUNCE_STATE)))
    except Exception:
        return set()


def _mark_announced(done):
    try:
        with open(ANNOUNCE_STATE, "w") as f:
            json.dump(sorted(done), f)
        os.chmod(ANNOUNCE_STATE, 0o600)
    except Exception:
        pass


def announce_pending(cfg):
    # ops_notify:false 的节点根本不碰运营群, 也就不该发接入说明 ——
    # 否则每轮都会白跑一次并在日志里留一条"失败", 白白制造噪音。
    if (cfg.get("alert") is False or not cfg.get("announce", True)
            or cfg.get("ops_notify", True) is False):
        return
    done = _announced()
    changed = False
    for n in (cfg.get("notify") or []):
        for chat in n.get("chats") or []:
            key = f"{chat}:{n.get('alias')}"
            if key in done:
                continue
            msg = ANNOUNCE_TPL.format(alias=n.get("alias", ""),
                                      domain=n.get("domain", ""),
                                      tz_name=n.get("tz_name", "本地"))
            ok, err = tg_send_chat(cfg, chat, msg, ctx=f"{n.get('alias')} 接入说明")
            if ok:
                done.add(key); changed = True
            # 失败不记状态, 下轮重试(还没入群的会在获批后自动补发); 原因照记, 别猜
            log_line(cfg, {"ev": "announce", "alias": n.get("alias"),
                           "chat": str(chat), "ok": ok, "err": err})
    if changed:
        _mark_announced(done)


# ------------------------------------------------------------- CF 凭据/zone

def read_ini(path):
    email = key = token = None
    with open(path) as f:
        for line in f:
            if "=" not in line or line.strip().startswith("#"):
                continue
            k, v = line.split("=", 1)
            k, v = k.strip(), v.strip()
            if k.endswith("api_token"):
                token = v
            elif k.endswith("email"):
                email = v
            elif k.endswith("api_key"):
                key = v
    return email, key, token


def cf_headers(acc):
    if acc.get("token"):
        return {"Authorization": "Bearer " + acc["token"],
                "Content-Type": "application/json", "User-Agent": UA}
    return {"X-Auth-Email": acc["email"], "X-Auth-Key": acc["key"],
            "Content-Type": "application/json", "User-Agent": UA}


def cf_get(acc, url):
    req = urllib.request.Request(url, headers=cf_headers(acc))
    with urllib.request.urlopen(req, timeout=25) as r:
        return json.load(r)


def cf_graphql(acc, query, variables):
    body = json.dumps({"query": query, "variables": variables}).encode()
    req = urllib.request.Request(GRAPHQL, data=body, headers=cf_headers(acc))
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.load(r)


def load_zones(acc):
    """拉一个账户下全部 zone。每 30 分钟刷新一次即可。"""
    out, page = {}, 1
    while True:
        d = cf_get(acc,
                   f"https://api.cloudflare.com/client/v4/zones?per_page=50&page={page}")
        if not d.get("success"):
            raise RuntimeError(json.dumps(d.get("errors"), ensure_ascii=False)[:200])
        for z in d["result"]:
            out[z["id"]] = z["name"]
        info = d.get("result_info") or {}
        if page >= (info.get("total_pages") or 1):
            break
        page += 1
    return out


Q_52X = """query($z:[String!],$s:Time!,$e:Time!,$codes:[Uint16!]){viewer{zones(filter:{zoneTag_in:$z},limit:100){
  zoneTag
  httpRequestsAdaptiveGroups(limit:200,
    filter:{datetime_geq:$s,datetime_leq:$e,edgeResponseStatus_in:$codes},
    orderBy:[datetimeMinute_ASC]){
    count dimensions{datetimeMinute clientRequestHTTPHost edgeResponseStatus coloCode}}}}}"""


# CF GraphQL 单次请求的 zone 数有硬上限, 超了直接报 "too many zones requested"。
# 实测 10 个可以, 所以按 10 个一批切开。ufa 账户 39 个 zone 就要发 4 次。
ZONES_PER_QUERY = 10

Q_52X = """query($z:[String!],$s:Time!,$e:Time!,$codes:[Uint16!]){viewer{zones(filter:{zoneTag_in:$z},limit:100){
  zoneTag
  httpRequestsAdaptiveGroups(limit:200,
    filter:{datetime_geq:$s,datetime_leq:$e,edgeResponseStatus_in:$codes},
    orderBy:[datetimeMinute_ASC]){
    count dimensions{datetimeMinute clientRequestHTTPHost edgeResponseStatus coloCode}}}}}"""


# CF GraphQL 单次请求的 zone 数有硬上限, 超了直接报 "too many zones requested"。
# 实测 10 个可以, 所以按 10 个一批切开。ufa 账户 39 个 zone 就要发 4 次。
ZONES_PER_QUERY = 10

_ip_cache = {}          # host -> (origin_ip, 过期时间戳)
_IP_CACHE_TTL = 1800


def origin_ip_of(acc, zone_id, host):
    """查 CF 上该主机名 A 记录指向的真实源站 IP。查不到返回 None。"""
    hit = _ip_cache.get(host)
    if hit and hit[1] > time.time():
        return hit[0]
    ip = None
    try:
        d = cf_get(acc,
                   "https://api.cloudflare.com/client/v4/zones/%s/dns_records?name=%s"
                   % (zone_id, urllib.parse.quote(host)))
        for r in (d.get("result") or []):
            if r.get("type") == "A":
                ip = r.get("content")
                break
    except Exception:
        pass
    _ip_cache[host] = (ip, time.time() + _IP_CACHE_TTL)
    return ip


def poll_cf_errors(acc, zones, lookback_min):
    """返回 [(minute, zone_name, host, status, colo, count)]"""
    if not zones:
        return []
    end = now_utc()
    start = end - datetime.timedelta(minutes=lookback_min)
    zids = list(zones.keys())
    rows = []
    for i in range(0, len(zids), ZONES_PER_QUERY):
        batch = zids[i:i + ZONES_PER_QUERY]
        d = cf_graphql(acc, Q_52X, {
            "z": batch,
            "s": start.strftime("%Y-%m-%dT%H:%M:%SZ"),
            "e": end.strftime("%Y-%m-%dT%H:%M:%SZ"),
            "codes": ORIGIN_ERR_CODES,
        })
        if d.get("errors"):
            raise RuntimeError(json.dumps(d["errors"], ensure_ascii=False)[:300])
        for z in d["data"]["viewer"]["zones"]:
            zname = zones.get(z["zoneTag"], z["zoneTag"])
            for g in z["httpRequestsAdaptiveGroups"]:
                dim = g["dimensions"]
                rows.append((dim["datetimeMinute"], zname, dim["clientRequestHTTPHost"],
                             int(dim["edgeResponseStatus"]), dim["coloCode"], g["count"],
                             z["zoneTag"]))
    return rows


# ------------------------------------------------------ zone 自动识别(zones_auto)
# 以前每台服务器轮询哪些 zone 是在 origins[].zones 里写死的, 建站/下线后忘了改就漏
# (09-30 uni 新建 uni210/266/288/345/366 没加进来; 同天下线 16 个旧 musicvk 没删, 报了
# 265 条 zone_missing)。现在自动算: 取两边交集 ——
#   ① CF: 本节点账户里, 有「橙云 A 记录」指向该服务器 IP 的 zone
#      (灰云不经过 CF, 本来就不会有 52x; 指向别处的 zone 自然排除, 例如 ufa 账户里的 ufa618.com)
#   ② nginx: dev 上 collect_bound.py 每小时采集的各机 nginx 实际绑定根域名
# 只在 CF 指过来、nginx 没绑的不轮询(落到默认站点, Full strict 下会报 526, 是误报来源);
# 两边对不上的只私聊提醒一次。origin 上 "cf_poll": false = 本节点不替它轮询 CF
# (例: mru 上的 genie/imdb, 它们与 mru 同机房, 归 dev 管)。
# nginx 数据缺失或超过 bound_max_age_sec(默认 24h)的那台, 退回只看 CF, 并提醒。
# 某个账户拉取失败时沿用它上一次的结果, 不会把监控范围清空。
BOUND_PATH = "/opt/site_manager/config/bound_domains.json"
ZONES_STATE = "/opt/site_manager/config/.zones_auto.json"


def _parse_ts(s):
    try:
        return datetime.datetime.strptime(s, "%Y-%m-%dT%H:%M:%SZ").replace(
            tzinfo=datetime.timezone.utc).timestamp()
    except Exception:
        return None


def load_proxied_ips(acc, zones):
    """{zid: zname} -> {zname: (zid, {橙云 A 记录指向的 IP}, {全部 A 记录指向的 IP})}"""
    out = {}
    for zid, zn in zones.items():
        ips, all_ips, page = set(), set(), 1
        while True:
            d = cf_get(acc,
                       f"https://api.cloudflare.com/client/v4/zones/{zid}/dns_records"
                       f"?type=A&per_page=100&page={page}")
            if not d.get("success"):
                raise RuntimeError(f"{zn}: " + json.dumps(d.get("errors"), ensure_ascii=False)[:150])
            for r in d["result"]:
                all_ips.add(r.get("content"))
                if r.get("proxied"):
                    ips.add(r.get("content"))
            info = d.get("result_info") or {}
            if page >= (info.get("total_pages") or 1):
                break
            page += 1
        out[zn] = (zid, ips, all_ips)
    return out


def load_bound(cfg, eligible):
    """-> ({origin: {根域名}} 新鲜的 nginx 数据, {origin: 退回只看 CF 的原因})"""
    max_age = cfg.get("bound_max_age_sec", 86400)
    try:
        hosts = json.load(open(BOUND_PATH)).get("hosts", {})
    except Exception:
        hosts = {}
    fresh, stale = {}, {}
    src = {o["name"]: o.get("bound_from") or o["name"] for o in cfg["origins"]}
    for on in eligible:
        h = hosts.get(src.get(on, on))          # bound_from: 同机多 IP 的, 借用宿主机的 nginx 数据
        ts = _parse_ts((h or {}).get("ts") or "")
        if not h or ts is None:
            stale[on] = "没有 nginx 绑定数据"
        elif time.time() - ts > max_age:
            stale[on] = f"nginx 绑定数据已过期({h['ts']})"
        else:
            fresh[on] = set(h.get("domains") or [])
    return fresh, stale


def discover_zones(cfg, prev=None):
    """自动算出每台服务器要轮询的 zone。返回:
      owner      {zone: origin}          用于把 52x 归到服务器
      acct_zones {账户: {zid: zone}}       每个账户要查的 zone
      by_origin  {origin: [zone]}
      cf_only    {origin: [zone]}          CF 橙云指过来, nginx 没绑 -> 不轮询
      nginx_only {origin: [zone]}          nginx 绑了, zone 在本节点账户里但 CF 完全没有记录指向本机
                                         (灰云指向本机的不算: 那是有意的, 如 musicvk 走俄罗斯只能灰云)
      fallback   {origin: 原因}            nginx 数据缺失/过期, 只看 CF
      errors     {账户: 原因}              拉取失败, 沿用上次结果"""
    eligible = [o["name"] for o in cfg["origins"] if o.get("cf_poll", True) is not False]
    ip2origin = {o["ip"]: o["name"] for o in cfg["origins"] if o["name"] in eligible}
    bound, stale = load_bound(cfg, eligible)
    res = {"owner": {}, "acct_zones": {}, "by_origin": {}, "cf_only": {}, "nginx_only": {},
           "fallback": {}, "errors": {}}
    in_accounts, zone_ips = set(), {}      # zone_ips: zone -> 全部 A 记录 IP(含灰云)
    origin_ip = {o["name"]: o["ip"] for o in cfg["origins"]}
    # 同一台机器(bound_from 相同)的几个 origin 视为一组: 域名指向组内任一 IP 都不算"指向别处"
    # (例: vk 2026-10-20 并入 imdb2 新机, vk 用 .107、imdb2 用 .106, nginx 是同一份)
    machine = {o["name"]: o.get("bound_from") or o["name"] for o in cfg["origins"]}
    group = {}
    for o in cfg["origins"]:
        group.setdefault(machine[o["name"]], set()).add(o["name"])
    peers = {on: group[machine[on]] for on in machine}
    for acc in cfg["accounts"]:
        an = acc["name"]
        try:
            targets = load_proxied_ips(acc, load_zones(acc))
        except Exception as ex:
            res["errors"][an] = str(ex)[:200]
            if prev:                               # 沿用上次这个账户的结果
                old = (prev.get("acct_zones") or {}).get(an) or {}
                res["acct_zones"][an] = dict(old)
                for zn in old.values():
                    if zn in prev["owner"]:
                        res["owner"][zn] = prev["owner"][zn]
                in_accounts |= set(old.values())
            continue
        in_accounts |= set(targets)
        for zn, (zid, ips, all_ips) in targets.items():
            zone_ips[zn] = all_ips
        for zn, (zid, ips, all_ips) in sorted(targets.items()):
            for on in sorted({ip2origin[ip] for ip in ips if ip in ip2origin}):
                if on in bound and zn not in bound[on]:
                    res["cf_only"].setdefault(on, []).append(zn)
                    continue
                if on in stale:
                    res["fallback"][on] = stale[on]
                if zn not in res["owner"]:         # 同一 zone 指向多台时归第一台
                    res["owner"][zn] = on
                    res["acct_zones"].setdefault(an, {})[zid] = zn
    for on, roots in bound.items():
        for zn in sorted(roots):
            grp = peers.get(on, {on})
            if zn in in_accounts and res["owner"].get(zn) not in grp \
                    and zn not in res["cf_only"].get(on, []) \
                    and not ({origin_ip.get(p) for p in grp} & zone_ips.get(zn, {origin_ip.get(on)})):
                res["nginx_only"].setdefault(on, []).append(zn)
    for zn, on in res["owner"].items():
        res["by_origin"].setdefault(on, []).append(zn)
    for v in list(res["by_origin"].values()) + list(res["cf_only"].values()) \
            + list(res["nginx_only"].values()):
        v.sort()
    return res


def zones_auto_notify(cfg, res):
    """监控范围有增减、或出现新的对不上, 私聊管理员一次; 状态落盘, 重启不重复提醒。
    首次运行(无状态文件)只记录基线不发消息。"""
    try:
        st = json.load(open(ZONES_STATE))
    except Exception:
        st = None
    cur = {on: zs for on, zs in res["by_origin"].items()}
    mism = set()
    for on, zs in res["cf_only"].items():
        mism |= {f"cf_only|{on}|{z}" for z in zs}
    for on, zs in res["nginx_only"].items():
        mism |= {f"nginx_only|{on}|{z}" for z in zs}
    mism |= {f"fallback|{on}" for on in res["fallback"]}
    lines = []
    if st is None:
        log_line(cfg, {"ev": "zones_auto_init",
                       "by_origin": {on: len(zs) for on, zs in cur.items()},
                       "mismatch": sorted(mism)})
        told = mism
    else:
        old = st.get("by_origin") or {}
        for on in sorted(set(old) | set(cur)):
            add = sorted(set(cur.get(on, [])) - set(old.get(on, [])))
            rm = sorted(set(old.get(on, [])) - set(cur.get(on, [])))
            if add:
                lines.append(f"➕ {on} 新增: {', '.join(add)}")
            if rm:
                lines.append(f"➖ {on} 移除: {', '.join(rm)}")
        new_m = sorted(mism - set(st.get("told") or []))
        for k in new_m:
            kind, on, *z = k.split("|")
            if kind == "cf_only":
                lines.append(f"⚠ {on}: {z[0]} 的橙云记录指向本机, 但 nginx 没绑定(未纳入轮询)")
            elif kind == "nginx_only":
                lines.append(f"⚠ {on}: nginx 绑定了 {z[0]}, 但 CF 上没有任何记录指向本机(指向别处/DNS 已删?)")
            else:
                lines.append(f"⚠ {on}: {res['fallback'][on]}, 暂时只按 CF 识别")
        told = mism                                # 已解决的忘掉, 再出现会再提醒
        if lines:
            log_line(cfg, {"ev": "zones_auto_change", "lines": lines})
            tg_send(cfg, "🔄 <b>CF 轮询范围自动更新</b>\n\n" + "\n".join(lines)
                    + (f"\n\n<i>监控节点: {cfg['node']}</i>" if cfg.get("node") else ""))
    try:
        with open(ZONES_STATE, "w") as f:
            json.dump({"by_origin": cur, "told": sorted(told), "ts": time.time()}, f,
                      ensure_ascii=False)
    except Exception:
        pass
    for an, err in res["errors"].items():
        log_line(cfg, {"ev": "zones_auto_error", "account": an, "err": err})


# --------------------------------------------------------------- 路由快照

# 机房排障时一定会要"访问的路由表"。故障只持续几分钟, 等收到告警再手工跑
# mtr 早就恢复了 —— 跑出来一切正常, 对方就会说"我们这边没问题"。
# 所以必须在探针失败的那一刻自动抓, 并且要有正常时的基线做对比。

_mtr_last = {}          # origin -> 上次抓取时间, 防止抖动时刷屏


def mtr_run(ip, mode="tcp", count=10, timeout=90):
    """跑一次 mtr, 返回报告文本。tcp 模式打 443, 与真实业务流量一致,
    比 ICMP 更有说服力(很多骨干对 ICMP 限速, 会产生假丢包)。"""
    cmd = ["mtr", "-r", "-n", "-w", "-c", str(count)]
    if mode == "tcp":
        cmd += ["--tcp", "--port", "443"]
    cmd.append(ip)
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
        return (r.stdout or r.stderr or "").strip()
    except Exception as ex:
        return f"(mtr 执行失败: {type(ex).__name__})"


def mtr_reached(text, target_ip):
    """从 mtr 报告判断是否真的打通到目的地。
    返回 (是否到达, 末跳丢包率)。中间跳的丢包一律忽略 —— 那多半是路由器
    对 ICMP 回包限速造成的假象, 只有末跳才算数。"""
    last = None
    for line in text.splitlines():
        parts = line.split()
        if len(parts) >= 3 and parts[0].rstrip(".|-").isdigit() and "--" in line:
            host = parts[2] if parts[1] == "|--" else parts[1]
            loss = None
            for tok in parts:
                if tok.endswith("%"):
                    try:
                        loss = float(tok.rstrip("%"))
                    except ValueError:
                        pass
                    break
            if host == target_ip:
                last = loss
    if last is None:
        return False, None
    return last < 50.0, last


def mtr_verdict(tcp_ok, icmp_ok):
    """三态判定。今早那次和 uni 这次的现象不同, 靠这个区分。"""
    if icmp_ok and not tcp_ok:
        return ("TCP 被选择性丢弃",
                "ICMP 全程畅通, 但 TCP 打不通 —— 链路是好的。要么上游有设备在丢 TCP"
                "(清洗/限速策略), 要么源站没在 accept。看 host_metrics 里那一分钟的 "
                "ListenOverflows 增量就能分清:有增量=源站, 没增量=上游。")
    if not icmp_ok and not tcp_ok:
        return ("链路中断", "ICMP 和 TCP 都不通 —— 整条路径断了, 直接找机房。")
    if tcp_ok and icmp_ok:
        return ("抓取时已恢复", "两种协议都通了, 故障窗口很短, 以事件日志的时间戳为准。")
    return ("ICMP 不通但 TCP 通", "多半是路径上限制了 ICMP, 参考价值有限。")


def mtr_capture(cfg, origin, reason):
    """故障现场取证。TCP 和 ICMP 必须并行跑 —— 串行差十几秒, 故障可能就在这十几秒里
    变化了, 两份数据对不上就失去了交叉判断的意义。"""
    ip, name = origin["ip"], origin["name"]
    d = os.path.join(os.path.dirname(cfg["log"]), "mtr")
    os.makedirs(d, exist_ok=True)
    stamp = now_utc().strftime("%Y%m%dT%H%M%SZ")

    res = {}
    ths = [threading.Thread(target=lambda mo: res.__setitem__(mo, mtr_run(ip, mo)),
                            args=(mode,)) for mode in ("tcp", "icmp")]
    for th in ths:
        th.start()
    for th in ths:
        th.join(timeout=120)
    tcp, icmp = res.get("tcp", "(超时)"), res.get("icmp", "(超时)")

    tcp_ok, tcp_loss = mtr_reached(tcp, ip)
    icmp_ok, icmp_loss = mtr_reached(icmp, ip)
    verdict_t, verdict_d = mtr_verdict(tcp_ok, icmp_ok)

    body = (f"# {name} ({ip})  {reason}\n"
            f"# 抓取时间 UTC {now_utc().strftime('%Y-%m-%d %H:%M:%S')}  节点 {cfg.get('node','')}\n"
            f"# 判定: {verdict_t}  (TCP末跳丢包={tcp_loss}%  ICMP末跳丢包={icmp_loss}%)\n"
            f"# {verdict_d}\n"
            f"\n===== TCP/443 =====\n{tcp}\n\n===== ICMP =====\n{icmp}\n")
    path = os.path.join(d, f"{name}-{stamp}.txt")
    with open(path, "w") as f:
        f.write(body)
    log_line(cfg, {"ev": "mtr_capture", "origin": name, "reason": reason, "file": path,
                   "verdict": verdict_t, "tcp_ok": tcp_ok, "icmp_ok": icmp_ok,
                   "tcp_loss": tcp_loss, "icmp_loss": icmp_loss})

    base = os.path.join(d, f"baseline-{name}.txt")
    tail = ""
    if os.path.exists(base):
        tail = "\n\n正常基线(对比用):\n<pre>" + _tail_table(open(base).read()) + "</pre>"
    tg_send(cfg, f"📍 <b>故障现场路由快照</b> — {name} ({ip})\n{reason}\n\n"
                 f"判定: <b>{verdict_t}</b>\n{verdict_d}\n\n"
                 f"TCP/443:\n<pre>{_tail_table(tcp)}</pre>\n"
                 f"ICMP:\n<pre>{_tail_table(icmp)}</pre>{tail}\n"
                 f"完整文件: <code>{path}</code>")


def _tail_table(text):
    """只留 mtr 的表格部分, 并转义 HTML"""
    lines = [l for l in text.splitlines() if l.strip()][:16]
    out = "\n".join(lines)
    return out.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


def mtr_capture_async(cfg, origin, reason, min_interval=300):
    name = origin["name"]
    if time.time() - _mtr_last.get(name, 0) < min_interval:
        return
    _mtr_last[name] = time.time()
    threading.Thread(target=mtr_capture, args=(cfg, origin, reason), daemon=True).start()


def mtr_baseline(cfg):
    """正常状态下的路由基线。没有基线, 故障快照就只是一张孤立的表,
    机房可以随口说'一直就这样'。"""
    d = os.path.join(os.path.dirname(cfg["log"]), "mtr")
    os.makedirs(d, exist_ok=True)
    for o in cfg["origins"]:
        if o.get("probe") is False:
            continue
        txt = mtr_run(o["ip"], "tcp")
        with open(os.path.join(d, f"baseline-{o['name']}.txt"), "w") as f:
            f.write(f"# {o['name']} ({o['ip']}) 正常基线\n"
                    f"# UTC {now_utc().strftime('%Y-%m-%d %H:%M:%S')}  节点 {cfg.get('node','')}\n\n{txt}\n")
    log_line(cfg, {"ev": "mtr_baseline", "n": len([o for o in cfg["origins"]
                                                   if o.get("probe") is not False])})


# ------------------------------------------------------------------- 探针

# ------------------------------------------------------- 地区(用于相关性判定)
#
# 与 fleet-status 的 REGION 保持一致。配置里给 origin 加 "region" 可覆盖。
# 不在表里又没配 region 的机器, 各自单独成区(返回值带机器名), 这样它永远不会
# 和别人凑成"整区失联", 也就不会被误降级。

DEFAULT_REGION = {"up": "日本", "gmg2": "美国", "uni-old": "美国",
                  "mru": "香港", "imdb": "香港", "genie": "香港",
                  "dev": "日本", "gmg": "日本", "uni2": "日本",
                  "imdb2": "日本", "imdb3": "日本", "uni": "日本", "vk": "日本",
                  "drama": "日本"}
# 2026-10-20: imdb2/imdb3/uni 迁到日本新机(与 dev 同机房); vk(musicvk) 同日并入 imdb2 新机(IP .107), 旧美国 uni(uni-old) 停业务   # gmg: 2026-10-06 起是日本新机(原 jp-win 重装), 旧香港 gmg 已于 09-12 下线


def region_of(o):
    return o.get("region") or DEFAULT_REGION.get(o["name"]) or ("未分区:" + o["name"])


def suspect_regions(cfg, state, failing=None, only_http=False):
    """判断哪些地区的"不可达"其实更可能是本节点自己的路径故障。

    依据: 一个节点如果把某地区的目标**全部**判成不可达, 而它在**别的地区**至少还有
    一个目标正常, 那么"本节点到该地区的路不通"比"该地区的机器同时全挂了"可能性大
    得多。2026-09-01 gmg2 就是这样: 香港的 gmg + mru 两台全判失败(273 秒), 而日本
    的 dev + jp-win 全程正常; 事后核实两台香港机器根本没断(nginx 全程有流量、CF 对
    其域名零 522、dev 探测零事件), 断的是 gmg2 自己到香港的路 —— 当时还往运营群推
    了一条根本不存在的中断。

    要求该地区至少有 2 个目标: 只有 1 个目标的地区"全灭"就是单机故障, 不该降级。
    若所有地区都没有正常目标, 说明本节点整个断网, 全部降级。

    failing: 判"失败"的谓词, 默认看 TCP(st["down"]); 应用层路径传自己的谓词。
    only_http: 只统计有 HTTPS 检查的目标(应用层路径用)。
    """
    failing = failing or (lambda st: st["down"])
    probed = [o for o in cfg["origins"] if o.get("probe") is not False
              and not (only_http and o.get("http") is False)]
    by_region = {}
    for o in probed:
        by_region.setdefault(region_of(o), []).append(o)

    healthy = set(r for r, os_ in by_region.items()
                  if any(not failing(state[x["name"]]) for x in os_))
    if not healthy and by_region:
        return set(by_region)            # 全区失联 = 本节点自己断了

    return set(r for r, os_ in by_region.items()
               if len(os_) >= 2 and all(failing(state[x["name"]]) for x in os_))


def fmt_suspect(origin, st, region, peers, node=""):
    """降级告警: 措辞上明确这是单节点视角、尚未获证实"""
    lines = ["🟡 <b>疑似不可达</b> — %s (%s)" % (origin["name"], origin["ip"]), "",
             "判定: <b>疑似本节点到「%s」的路径故障</b>" % region,
             "本节点在「%s」的目标已全部失联, 但其他地区正常 —— "
             "更可能是路不通, 而不是这些机器同时挂了。" % region, "",
             "裸 IP 探针: ❌ 不通 (连续失败 %d 次)" % st["fail"]]
    if peers:
        lines.append("")
        lines.append("同期其他机器:")
        for name, ok in peers:
            lines.append("  • %s: %s" % (name, "✅ 正常" if ok else "❌ 不通"))
    lines += ["", "⚠️ 未推送运营群 —— 需要另一节点的数据交叉确认后才能定性。"]
    if node:
        lines += ["", "<i>监控节点: %s</i>" % node]
    return "\n".join(lines)


def probe_tcp(ip, port, timeout):
    """裸 IP TCP 连通性 —— 绕开 CF, 直接量链路。返回 (ok, 毫秒/错误)"""
    t0 = time.time()
    try:
        with socket.create_connection((ip, port), timeout=timeout):
            return True, int((time.time() - t0) * 1000)
    except Exception as ex:
        return False, type(ex).__name__


def probe_https(ip, host, timeout):
    """带 SNI 的 HTTPS GET, 强制解析到指定 IP —— 验证应用层"""
    try:
        out = subprocess.run(
            ["curl", "-sS", "-o", "/dev/null", "-w", "%{http_code}",
             "--resolve", f"{host}:443:{ip}", "-m", str(timeout),
             f"https://{host}/"],
            capture_output=True, text=True, timeout=timeout + 5)
        code = (out.stdout or "").strip()
        return (code.isdigit() and code != "000"), code or (out.stderr or "").strip()[:60]
    except Exception as ex:
        return False, type(ex).__name__


# ------------------------------------------- 第二票: 本节点黑匣子 / 对端 / 目标机 / CF
#
# 单节点视角永远分不清"对面挂了"和"我到对面的路挂了"。推运营群之前必须拿到第二票,
# 票源四个, 全是现成的:
#   1. 本节点黑匣子  自己出网都在丢包, 看到的一切失败都不作数           -> denied
#   2. 对端观测点    走不同入口的 dev/mru: 它连得上 = 是我的路          -> denied
#                    它也连不上 = 两条入口都断, 是对面                  -> confirmed
#   3. 目标机自检    经对端 ssh 让目标机自报: 能否出外网 / 443 在线连接 / 接不住
#                    不参与判决, 但写进告警, 一眼看出"机器活着只是路断了"
#   4. CF 52x        用户侧真的报错了, 这是最直接的"受影响"证据          -> confirmed
# 三种结论: denied 不推 / confirmed 推 / unknown 先不推, 主循环每分钟再问一次。

BLACKBOX_LOG = "/opt/site_manager/logs/host_metrics.jsonl"


def own_blackbox(max_age=180):
    """本节点黑匣子最近一行; 没有或超过 max_age 秒返回 None"""
    try:
        with open(BLACKBOX_LOG, "rb") as f:
            f.seek(0, 2)
            f.seek(max(0, f.tell() - 4096))
            tail = f.read().decode(errors="ignore")
        row = json.loads([l for l in tail.splitlines() if l.startswith("{")][-1])
        ts = datetime.datetime.strptime(row["ts"], "%Y-%m-%dT%H:%M:%SZ").replace(
            tzinfo=datetime.timezone.utc)
        return row if (now_utc() - ts).total_seconds() <= max_age else None
    except Exception:
        return None


def _sh(cmd, timeout):
    """跑一条 shell 命令。返回 (rc, stdout, stderr); 超时 rc=-1"""
    try:
        r = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=timeout)
        return r.returncode, r.stdout or "", r.stderr or ""
    except subprocess.TimeoutExpired:
        return -1, "", "timeout"
    except Exception as ex:
        return -1, "", type(ex).__name__


def _last_json(out):
    try:
        return json.loads([l for l in out.strip().splitlines() if l.startswith("{")][-1])
    except Exception:
        return None


def target_self_check(o, timeout=25):
    """经 ssh 让目标机自报状态(host_metrics.py --peek)。需要 origin 配了 ssh 别名"""
    alias = o.get("ssh")
    if not alias:
        return None, "本节点无 ssh 通道"
    rc, out, err = _sh(f"ssh -o BatchMode=yes -o ConnectTimeout=6 "
                       f"-o StrictHostKeyChecking=accept-new {alias} "
                       f"python3 /opt/site_manager/scripts/host_metrics.py --peek", timeout)
    if rc != 0:
        return None, ((err.strip().splitlines() or ["ssh 失败"])[-1])[:80]
    v = _last_json(out)
    return (v, None) if v else (None, "输出不是 JSON")


def peek_origin(cfg, o, with_target=True):
    """本节点对某台的即时视角: TCP / HTTPS / (可选)目标机自检。给对端节点调用, 也给 --peek 用"""
    tcp_ok, tcp_info = probe_tcp(o["ip"], o.get("port", 443), cfg.get("probe_timeout", 5))
    res = {"node": cfg.get("node", ""), "origin": o["name"], "ip": o["ip"],
           "ts": now_utc().strftime("%Y-%m-%dT%H:%M:%SZ"),
           "tcp": tcp_ok, "tcp_info": tcp_info, "https": None, "code": None,
           "node_out_loss": (own_blackbox() or {}).get("peer_loss_pct"),
           "target": None, "target_err": None}
    if o.get("http") is not False:
        res["https"], res["code"] = probe_https(o["ip"], o["host"],
                                                cfg.get("probe_timeout", 5) + 3)
    if with_target:
        res["target"], res["target_err"] = target_self_check(o)
    return res


def peer_peek(cfg, peer, origin_name):
    """问对端观测点它现在怎么看这台。peer = {"name":..., "ssh": "ssh ... user@host", "cmd": ...}
    cmd 默认 "peek {origin}" —— 对端 authorized_keys 用 command= 锁死成 --peek-forced,
    这边发什么都只会得到 peek。对端是普通 shell(有完整 ssh 权限的方向, 如 dev->mru)时配:
      "cmd": "SSH_ORIGINAL_COMMAND='peek {origin}' python3 /opt/site_manager/scripts/cf_origin_watch.py --peek-forced"
    """
    cmd = peer.get("cmd", "peek {origin}").format(origin=origin_name)
    rc, out, err = _sh(f"{peer['ssh']} \"{cmd}\"", peer.get("timeout", 45))
    if rc != 0:
        return None, ((err.strip().splitlines() or ["ssh 失败"])[-1])[:80]
    v = _last_json(out)
    return (v, None) if v else (None, "输出不是 JSON: " + out.strip()[:60])


def target_isolated(tg):
    """目标机自检里"机器被隔离"的信号: 自己出不了外网(HTTPS) 且 443 在线连接归零。
    两个条件必须同时成立 —— 夜里 443 本来就是 0, 单看归零会误判; 单看出不了外网可能是 DNS。
    2026-09-14 17:05Z uni/gmg2 被机房入口吞 TCP 时就是这个样子: ping 通、curl 出不去、
    443 从 13/26 掉到 0, 而日本 dev 的入口毫发无损 —— 只信对端那一票就漏报了。"""
    if not tg:
        return False
    last = tg.get("last") or {}
    return (tg.get("out_ok") is False and tg.get("est_443") == 0
            and (last.get("est_443") or 0) > 0)


def confirm_outage(cfg, o, kind, cf_recent_ts, suspect=False, since=None):
    """推运营群前的第二票。kind: 'down'(TCP 不通) | 'app_down'(HTTPS 失败)
    suspect: 地区相关性已经怀疑是本节点的路(拿不到对端票时按 denied 处理)
    since:   本次故障开始时间。对端能连上 ≠ 没故障(可能只是它那条入口没断), 所以"对端通"
             不立刻否决, 而是等 CF 数据(有 1~2 分钟延迟)到 confirm_window_sec 为止;
             窗口内 CF 出现 52x -> confirmed, 窗口过了还没有 -> denied。
    返回 {"verdict": confirmed|denied|unknown, "reasons": [...], "peers": [...], "target": {...}|None}"""
    res = {"verdict": "unknown", "reasons": [], "peers": [], "target": None, "cf": False}
    lookback = cfg.get("cf_lookback_min", 5) * 60 + 60
    res["cf"] = bool(cf_recent_ts and time.time() - cf_recent_ts <= lookback)
    window_left = (since + cfg.get("confirm_window_sec", 420) - time.time()) if since else 0

    # 1. 自己出网都在丢包 -> 看到的失败不作数
    loss = (own_blackbox() or {}).get("peer_loss_pct")
    if loss is not None and loss >= cfg.get("self_loss_deny_pct", 30):
        res["verdict"] = "denied"
        res["reasons"].append(f"本节点黑匣子出网丢包 {loss}% —— 是本节点的路, 不是对面")
        return res

    # 2. 目标机自检(本节点自己有 ssh 通道时先拿, 只要几百毫秒; 没有的话等对端带回来)。
    #    不参与判决 —— 22 通 443 不通是 nginx/防火墙的事, 照样是故障 —— 但要写进告警。
    if o.get("ssh"):
        res["target"], _ = target_self_check(o)

    # 3. 对端观测点
    peer_ok = False
    for p in cfg.get("peers") or []:
        if p["name"] == o["name"]:
            res["reasons"].append(f"对端 {p['name']} 就是目标机, 不能给自己投票")
            continue
        v, err = peer_peek(cfg, p, o["name"])
        if v is None:
            res["peers"].append({"name": p["name"], "ok": None, "err": err})
            res["reasons"].append(f"对端 {p['name']} 问不到: {err}")
            continue
        if v.get("target") and res["target"] is None:
            res["target"] = v["target"]
        sees_ok = v.get("tcp") if kind == "down" else (
            v.get("https") if v.get("https") is not None else v.get("tcp"))
        res["peers"].append({"name": p["name"], "ok": bool(sees_ok),
                             "tcp": v.get("tcp"), "code": v.get("code"),
                             "out_loss": v.get("node_out_loss")})
        if sees_ok:
            peer_ok = True
            res["reasons"].append(f"对端 {p['name']} 能连上"
                                  f"(TCP {'✅' if v.get('tcp') else '❌'} / HTTPS {v.get('code')})")
        else:
            res["verdict"] = "confirmed"
            res["reasons"].append(f"对端 {p['name']} 也连不上"
                                  f"(TCP {v.get('tcp_info')} / HTTPS {v.get('code')})")

    # 4. 目标机自检说自己被隔离了 —— 比对端那一票更硬(对端通可能只是它那条入口没断)
    if target_isolated(res["target"]):
        res["verdict"] = "confirmed"
        res["reasons"].append("目标机自检: 出不了外网且 443 在线连接归零 —— 机器被隔离, 对端能连只是个别入口")

    # 5. CF 52x
    if res["cf"]:
        res["verdict"] = "confirmed"
        res["reasons"].append("CF 最近 5 分钟有 52x —— 用户侧已受影响"
                              + (", 对端能连只是部分路径" if peer_ok else ""))
    if res["verdict"] == "confirmed":
        return res

    # 6. 没有确认票。对端通 / 地区怀疑 = 倾向否决, 但 CF 数据有 1~2 分钟延迟, 在窗口内先挂起等它
    if peer_ok or suspect:
        if window_left > 0:
            res["verdict"] = "unknown"
            res["reasons"].append(f"倾向本节点路径问题, 但 CF 数据有延迟 —— 再等 {int(window_left)} 秒看有没有 52x")
        else:
            res["verdict"] = "denied"
            res["reasons"].append("窗口内 CF 始终无 52x —— 判为本节点路径故障, 不推运营群")
    else:
        res["reasons"].append("无对端票、CF 无 52x —— 暂不推运营群, 每分钟再问")
    return res


def fmt_target(tg):
    """目标机自检一行"""
    if not tg:
        return "目标机自检: —(拿不到)"
    last = tg.get("last") or {}
    out = ("✅ 出外网正常" if tg.get("out_ok")
           else ("⚠️ HTTPS 出不去但能 ping" if tg.get("out_ping_ok") else "❌ 出不了外网"))
    return (f"目标机自检({tg.get('host', '?')}): {out} · 443 在线 {tg.get('est_443', '-')}"
            f" · 接不住 {last.get('ListenOverflows', '-')} · 出网丢包 {last.get('peer_loss_pct', '-')}%"
            f" · 负载 {tg.get('load1', '-')}")


def fmt_confirm(res):
    head = {"confirmed": "✅ 第二票已确认 —— 已推运营群",
            "denied": "🟡 第二票否决 —— 是本节点的路, 未推运营群",
            "unknown": "⏳ 未获第二票 —— 暂不推运营群, 每分钟再问"}[res["verdict"]]
    lines = [head] + [f"  • {r}" for r in res["reasons"]]
    lines.append(fmt_target(res.get("target")))
    return "\n".join(lines)


# ------------------------------------------------------------------ 判因

def verdict(probe_down, cf_err):
    if probe_down and cf_err:
        return "源站链路问题", "找机房 —— 探针直连裸 IP 也不通, 说明不是 CDN 的锅"
    if not probe_down and cf_err:
        return "CF 回源路径问题", "找 Cloudflare —— 源站从外部直连正常, 只有 CF 回源失败"
    if probe_down and not cf_err:
        return "探针侧网络问题", "先看监控机自己的网络 —— 用户侧无 52x, 影响面可能有限"
    return "正常", ""


def fmt_alert(kind, origin, st, cf_summary, others, node=""):
    has_probe = origin.get("probe") is not False
    lines = [f"🔴 <b>{kind}</b> — {origin['name']} ({origin['ip']})", ""]
    if has_probe:
        v, advice = verdict(st["down"], bool(cf_summary))
        lines.append(f"判定: <b>{v}</b>")
        if advice:
            lines.append(advice)
    else:
        lines.append("判定: <b>无探针数据</b>")
        lines.append("本节点与该机器同内网, 无法从外部探测 —— 判因请参考另一监控节点")
    lines.append("")
    if has_probe:
        lines.append(f"裸 IP 探针: {'❌ 不通' if st['down'] else '✅ 正常'}"
                     + (f" (连续失败 {st['fail']} 次)" if st["down"] else ""))
    else:
        lines.append("裸 IP 探针: — (本节点不探测)")
    if cf_summary:
        lines.append("CF 源站错误:")
        for (host, code), n in sorted(cf_summary.items(), key=lambda kv: -kv[1])[:6]:
            lines.append(f"  • {host} — {code} × {n}")
    else:
        lines.append("CF 源站错误: 无")
    if others:
        lines.append("")
        lines.append("同期其他机器:")
        for name, ok in others:
            lines.append(f"  • {name}: {'✅ 正常' if ok else '❌ 不通'}")
    if node:
        lines.append("")
        lines.append(f"<i>监控节点: {node}</i>")
    return "\n".join(lines)


# ------------------------------------------------------------------- 主循环

def load_conf():
    with open(CONF_PATH) as f:
        cfg = json.load(f)
    ok = []
    for acc in cfg["accounts"]:
        if not os.path.exists(acc["ini"]):
            print(f"[warn] 跳过账户 {acc['name']}: 凭据文件不存在 {acc['ini']}", file=sys.stderr)
            continue
        acc["email"], acc["key"], acc["token"] = read_ini(acc["ini"])
        if not (acc.get("token") or (acc["email"] and acc["key"])):
            print(f"[warn] 跳过账户 {acc['name']}: 凭据文件缺 email 或 api_key", file=sys.stderr)
            continue
        ok.append(acc)
    cfg["accounts"] = ok
    if not ok:
        print("[warn] 没有可用的 CF 账户, 只有裸 IP 探针会工作", file=sys.stderr)
    return cfg


def run(cfg, once=False):
    state = {o["name"]: {"fail": 0, "down": False, "since": None, "alerted": False,
                         "app_fail": 0, "app_alerted": False, "app_since": None,
                         # 异常通知真正送达了哪些运营群 —— 恢复通知照着这个发
                         "ops_chats": set(), "app_ops_chats": set(),
                         # 本次判定是否被地区相关性降级为"疑似"
                         "suspect": False, "app_suspect": False,
                         # 第二票没拿到时挂起的运营群播报: None | "down" | "app_down"
                         "ops_pending": None, "last_confirm": 0.0}
             for o in cfg["origins"]}
    cf_state = {}          # account -> {"zones": {zid: zname}, "next_refresh": ts}
    cf_alerted = {}        # origin -> 是否已就 CF 错误告警过
    cf_recent = {}         # origin -> 最近一次 CF 52x(非噪音)的时间戳, 第二票用
    reported = {}          # (minute, host, status, colo) -> 已上报的次数

    # zone -> 归属服务器, 以及每个账户需要查哪些 zone。都来自配置里各 origin 的 zones 字段。
    # zones_auto: true 时每 zones_refresh_sec 自动重算(见 discover_zones), 写死的 zones
    # 只在自动识别第一次就整体失败时兜底。
    zone_owner, wanted = {}, {}
    for o in cfg["origins"]:
        zs_cfg = o.get("zones") or {}
        for an, zs in (zs_cfg.items() if isinstance(zs_cfg, dict) else []):
            wanted.setdefault(an, set()).update(zs)
            for z in zs:
                zone_owner[z] = o["name"]
    disc, next_disc = None, 0.0
    last_cf = 0.0
    last_probe = 0.0
    last_prune = 0.0
    last_baseline = 0.0
    last_announce = 0.0
    last_sweep = 0.0

    while True:
        t = time.time()

        # ---- 裸 IP 探针
        if t - last_probe >= cfg["probe_sec"]:
            last_probe = t
            for o in cfg["origins"]:
                if o.get("probe") is False:
                    continue
                ok, info = probe_tcp(o["ip"], o.get("port", 443), cfg.get("probe_timeout", 5))
                st = state[o["name"]]
                if ok:
                    if st["down"]:
                        dur = int(t - st["since"]) if st["since"] else 0
                        log_line(cfg, {"ev": "origin_up", "origin": o["name"],
                                       "down_sec": dur, "suspect_path": st["suspect"]})
                        if st["alerted"]:
                            # 只发给当初真正收到过异常通知的群。降级告警压根没推过运营群,
                            # ops_chats 为空, 这里自然也不发 —— 不会再出现孤零零的"已恢复"
                            if st["ops_chats"]:
                                notify_ops(cfg, o["name"], "up", dur,
                                           only_chats=st["ops_chats"])
                            else:
                                log_line(cfg, {"ev": "ops_notify_skip", "origin": o["name"],
                                               "event": "up",
                                               "why": "异常通知未送达或已降级, 不发恢复"})
                            head = ("🟡 <b>疑似不可达已恢复</b>" if st["suspect"]
                                    else "🟢 <b>已恢复</b>")
                            tg_send(cfg, f"{head} — {o['name']} ({o['ip']})\n"
                                         f"裸 IP 探针恢复连通, 本次持续 {dur} 秒"
                                         + (f"\n\n<i>监控节点: {cfg['node']}</i>" if cfg.get("node") else ""))
                        st.update(down=False, since=None, alerted=False,
                                  ops_chats=set(), suspect=False)
                        if st["ops_pending"] == "down":
                            st["ops_pending"] = None
                    st["fail"] = 0
                else:
                    st["fail"] += 1
                    log_line(cfg, {"ev": "probe_fail", "origin": o["name"],
                                   "n": st["fail"], "err": info})
                    # 第一次失败就开抓 —— 故障常常只有几分钟, 等确认完就来不及了
                    mtr_capture_async(cfg, o, f"裸 IP 探针失败({info})")
                    if st["fail"] >= cfg["probe_fail_threshold"] and not st["down"]:
                        st.update(down=True, since=t)

        # ---- 应用层检查(与 CF 轮询同频)。TCP 通但 HTTPS 挂 = nginx/PHP 挂了,
        #      跟链路断是完全不同的故障,要分开告警。
        if t - last_cf >= cfg["poll_cf_sec"]:
            # 先把所有目标探完再判 —— 判定要看"同区其他目标此刻怎么样", 边探边判的话
            # 第一台到阈值时其他台还停在上一轮的计数, 地区相关性永远只对最后一台生效。
            app_res = {}
            for o in cfg["origins"]:
                if o.get("probe") is False or o.get("http") is False:
                    continue          # http:false = 该机没有 web 服务, 只做 TCP 探测
                st = state[o["name"]]
                if st["down"]:
                    continue          # 链路都不通,应用层没有单独判断的意义
                ok, info = probe_https(o["ip"], o["host"], cfg.get("probe_timeout", 5) + 3)
                app_res[o["name"]] = (ok, info)
                if not ok:
                    st["app_fail"] += 1
                    log_line(cfg, {"ev": "app_fail", "origin": o["name"],
                                   "n": st["app_fail"], "err": info})
            sus_app = suspect_regions(cfg, state, only_http=True,
                                      failing=lambda s: s["down"] or s["app_fail"] >= 1)
            for o in cfg["origins"]:
                if o["name"] not in app_res:
                    continue
                st = state[o["name"]]
                ok, info = app_res[o["name"]]
                if ok:
                    if st["app_alerted"]:
                        tg_send(cfg, f"🟢 <b>已恢复</b> — {o['name']} 应用层恢复正常 (HTTP {info})"
                                     + (" (此前被判为本节点路径问题)" if st["app_suspect"] else ""))
                        log_line(cfg, {"ev": "app_up", "origin": o["name"], "code": info,
                                       "suspect_path": st["app_suspect"]})
                        dur = int(t - st.get("app_since", t))
                        if st["app_ops_chats"]:
                            notify_ops(cfg, o["name"], "up", dur,
                                       only_chats=st["app_ops_chats"])
                        else:
                            log_line(cfg, {"ev": "ops_notify_skip", "origin": o["name"],
                                           "event": "app_up",
                                           "why": "异常通知未送达或未获第二票, 不发恢复"})
                    if st["ops_pending"] == "app_down":
                        st["ops_pending"] = None
                    st.update(app_fail=0, app_alerted=False, app_ops_chats=set(),
                              app_suspect=False)
                elif st["app_fail"] >= 2 and not st["app_alerted"]:
                    st["app_alerted"] = True
                    st["app_since"] = t
                    st["app_suspect"] = region_of(o) in sus_app
                    conf = confirm_outage(cfg, o, "app_down", cf_recent.get(o["name"]),
                                          suspect=st["app_suspect"], since=st["app_since"])
                    st["last_confirm"] = t
                    log_line(cfg, {"ev": "confirm", "origin": o["name"], "kind": "app_down",
                                   "verdict": conf["verdict"], "suspect_region": st["app_suspect"],
                                   "reasons": conf["reasons"], "peers": conf["peers"],
                                   "target": conf.get("target")})
                    if conf["verdict"] == "confirmed":
                        st["app_ops_chats"] = notify_ops(cfg, o["name"], "app_down")
                    elif conf["verdict"] == "unknown":
                        st["ops_pending"] = "app_down"
                    tg_send(cfg,
                        f"🔴 <b>源站应用层异常</b> — {o['name']} ({o['ip']})\n\n"
                        f"判定: <b>{'疑似本节点路径问题' if st['app_suspect'] else '网络正常但服务异常'}</b>\n"
                        + ("本节点在该地区的 HTTPS 目标同时失败, 更像是路不通\n\n"
                           if st["app_suspect"] else
                           "裸 IP 的 443 端口 TCP 可连通, 但 HTTPS 请求失败 —— "
                           "排查 nginx / php-fpm / 证书, 不是链路问题\n\n")
                        + f"域名: {o['host']}\n返回: {info}\n\n"
                        + fmt_confirm(conf)
                        + (f"\n\n<i>监控节点: {cfg['node']}</i>" if cfg.get("node") else ""))

        # ---- CF 52x 轮询
        # 只查这 7 台服务器 nginx 上实际绑定的域名所在的 zone。一个 CF 账户下往往
        # 还混着别处的站点(例:ufa 账户里 ufa618.com 的源站是 103.84.87.42,不在机队里),
        # 不收窄的话它们的 52x 会被算到共用同一账户的服务器头上,造成误报。
        if t - last_cf >= cfg["poll_cf_sec"]:
            last_cf = t
            if cfg.get("zones_auto") and t >= next_disc:
                next_disc = t + cfg.get("zones_refresh_sec", 3600)
                try:
                    new = discover_zones(cfg, prev=disc)
                except Exception as ex:
                    new = None
                    log_line(cfg, {"ev": "zones_auto_error", "account": "*", "err": str(ex)[:200]})
                if new and (new["acct_zones"] or disc is not None):
                    disc = new
                    zone_owner = dict(new["owner"])
                    wanted = {an: set(zs.values()) for an, zs in new["acct_zones"].items()}
                    for acc in cfg["accounts"]:   # zone id 已在识别时拿到, 不再按名字刷新
                        cf_state[acc["name"]] = {"zones": dict(new["acct_zones"].get(acc["name"]) or {}),
                                                 "next_refresh": float("inf")}
                    zones_auto_notify(cfg, new)
            all_rows = []
            for acc in cfg["accounts"]:
                want = wanted.get(acc["name"])
                if not want:
                    continue
                cs = cf_state.setdefault(acc["name"], {"zones": {}, "next_refresh": 0})
                try:
                    if t >= cs["next_refresh"]:
                        cs["zones"] = {zid: zn for zid, zn in load_zones(acc).items()
                                       if zn in want}
                        cs["next_refresh"] = t + 1800
                        miss = want - set(cs["zones"].values())
                        if miss:
                            log_line(cfg, {"ev": "zone_missing", "account": acc["name"],
                                           "zones": sorted(miss)})
                    all_rows += poll_cf_errors(acc, cs["zones"], cfg.get("cf_lookback_min", 5))
                except Exception as ex:
                    log_line(cfg, {"ev": "cf_poll_error", "account": acc["name"],
                                   "err": str(ex)[:200]})

            # 增量去重:lookback 窗口每轮都会重叠,而且同一分钟的数据还会继续补齐。
            # 按完整维度记住"已上报的次数",只处理增量,既不重复计数也不用等数据稳定。
            fresh = []
            for r in all_rows:
                key = (r[0], r[2], r[3], r[4])       # minute, host, status, colo
                delta = r[5] - reported.get(key, 0)
                if delta > 0:
                    reported[key] = r[5]
                    fresh.append((r[0], r[1], r[2], r[3], r[4], delta))
            if len(reported) > 20000:
                keep_after = (now_utc() - datetime.timedelta(
                    minutes=cfg.get("cf_lookback_min", 5) + 5)).strftime("%Y-%m-%dT%H:%M:%SZ")
                for k in [k for k in reported if k[0] < keep_after]:
                    del reported[k]

            for r in fresh:
                rec = {"ev": "cf_52x", "minute": r[0], "zone": r[1], "host": r[2],
                       "status": r[3], "colo": r[4], "count": r[5],
                       "origin": zone_owner.get(r[1], "?")}
                if is_port_noise(cfg, r[2]):
                    rec["noise"] = "nonstandard_port"
                log_line(cfg, rec)

            # 按服务器归拢后再判断告警 —— zone 属于谁是配置里写死的,不用猜
            by_origin = {}
            for r in fresh:
                if is_port_noise(cfg, r[2]):
                    continue          # 非标端口 = 扫描器打的, 不计入告警
                oname = zone_owner.get(r[1])
                if oname:
                    by_origin.setdefault(oname, []).append(r)

            for o in cfg["origins"]:
                rows = by_origin.get(o["name"], [])
                total = sum(r[5] for r in rows)
                if total > 0:
                    cf_recent[o["name"]] = t     # 第二票: 用户侧确实在报 52x
                was = cf_alerted.get(o["name"], False)
                if total >= cfg.get("cf_52x_threshold", 5) and not was:
                    cf_alerted[o["name"]] = True
                    summary = {}
                    for r in rows:
                        summary[(r[2], r[3])] = summary.get((r[2], r[3]), 0) + r[5]
                    others = [(x["name"], not state[x["name"]]["down"])
                              for x in cfg["origins"]
                              if x["name"] != o["name"] and x.get("probe") is not False]
                    tg_send(cfg, fmt_alert("CF 源站错误", o, state[o["name"]], summary,
                                           others, cfg.get("node", "")))
                    if o.get("probe") is not False:
                        mtr_capture_async(cfg, o, f"CF 源站错误 {total} 次")
                elif not rows and was:
                    cf_alerted[o["name"]] = False
                    tg_send(cfg, f"🟢 <b>已恢复</b> — {o['name']} 的 CF 源站错误已停止"
                                 + (f"\n\n<i>监控节点: {cfg['node']}</i>" if cfg.get("node") else ""))

        # ---- 探针告警(放在 CF 轮询之后, 这样能带上 CF 侧信息)
        #
        # 告警前先做地区相关性判定:整个地区的目标全挂、而别的地区正常, 多半是本节点
        # 到那边的路断了, 不是那些机器都挂了。这类降级为"疑似", 管理员照收、路由照抓,
        # 但不推运营群 —— 运营群只接收够格定性的事件。
        sus = suspect_regions(cfg, state)
        for o in cfg["origins"]:
            st = state[o["name"]]
            if st["down"] and not st["alerted"]:
                st["alerted"] = True
                others = [(x["name"], not state[x["name"]]["down"])
                          for x in cfg["origins"]
                          if x["name"] != o["name"] and x.get("probe") is not False]
                reg = region_of(o)
                st["suspect"] = reg in sus
                # 第二票: 地区相关性只是怀疑, 对端观测点说了才算。整个机房真断了
                # (08-28 那种)从单节点看和"我到机房的路断了"一模一样, 只有对端也连不上
                # 才能把"疑似"升回"确认"并推运营群。
                conf = confirm_outage(cfg, o, "down", cf_recent.get(o["name"]),
                                      suspect=st["suspect"], since=st["since"])
                st["last_confirm"] = t
                log_line(cfg, {"ev": "origin_down", "origin": o["name"],
                               "region": reg, "suspect_path": st["suspect"],
                               "verdict": conf["verdict"]})
                log_line(cfg, {"ev": "confirm", "origin": o["name"], "kind": "down",
                               "verdict": conf["verdict"], "suspect_region": st["suspect"],
                               "reasons": conf["reasons"], "peers": conf["peers"],
                               "target": conf.get("target")})
                if conf["verdict"] == "confirmed":
                    st["suspect"] = False
                    tg_send(cfg, fmt_alert("源站不可达", o, st, {}, others, cfg.get("node", ""))
                                 + "\n\n" + fmt_confirm(conf))
                    st["ops_chats"] = notify_ops(cfg, o["name"], "down")
                else:
                    if conf["verdict"] == "unknown":
                        st["ops_pending"] = "down"
                    body = (fmt_suspect(o, st, reg, others, cfg.get("node", ""))
                            if st["suspect"] else
                            fmt_alert("源站不可达", o, st, {}, others, cfg.get("node", "")))
                    tg_send(cfg, body + "\n\n" + fmt_confirm(conf))

        # ---- 第二票没拿到的, 每分钟再问一次; 拿到确认就补推运营群
        for o in cfg["origins"]:
            st = state[o["name"]]
            if not st["ops_pending"] or t - st["last_confirm"] < cfg.get("confirm_retry_sec", 60):
                continue
            kind = st["ops_pending"]
            still = st["down"] if kind == "down" else (st["app_alerted"] and not st["down"])
            if not still:
                st["ops_pending"] = None
                continue
            conf = confirm_outage(cfg, o, kind, cf_recent.get(o["name"]),
                                  suspect=st["suspect"] if kind == "down" else st["app_suspect"],
                                  since=st["since"] if kind == "down" else st.get("app_since"))
            st["last_confirm"] = t
            log_line(cfg, {"ev": "confirm", "origin": o["name"], "kind": kind, "retry": True,
                           "verdict": conf["verdict"], "reasons": conf["reasons"],
                           "peers": conf["peers"], "target": conf.get("target")})
            if conf["verdict"] == "confirmed":
                st["ops_pending"] = None
                chats = notify_ops(cfg, o["name"], kind)
                if kind == "down":
                    st["ops_chats"], st["suspect"] = chats, False
                else:
                    st["app_ops_chats"], st["app_suspect"] = chats, False
                tg_send(cfg, f"✅ <b>第二票补到 —— 已推运营群</b> — {o['name']} ({o['ip']})\n\n"
                             + fmt_confirm(conf))
            elif conf["verdict"] == "denied":
                st["ops_pending"] = None
                tg_send(cfg, f"🟡 <b>第二票否决</b> — {o['name']} ({o['ip']})\n\n" + fmt_confirm(conf))

        if t - last_announce >= 300:
            last_announce = t
            try:
                announce_pending(cfg)
            except Exception as ex:
                log_line(cfg, {"ev": "announce_error", "err": str(ex)[:200]})

        if t - last_sweep >= 60:
            last_sweep = t
            try:
                sweep_ephemeral(cfg)
            except Exception as ex:
                log_line(cfg, {"ev": "ops_del_error", "err": str(ex)[:200]})

        if t - last_baseline >= cfg.get("mtr_baseline_sec", 86400):
            last_baseline = t
            threading.Thread(target=mtr_baseline, args=(cfg,), daemon=True).start()

        if t - last_prune >= 3600:
            last_prune = t
            prune_log(cfg)

        if once:
            return
        time.sleep(cfg.get("tick_sec", 5))


# ------------------------------------------------------------------ 报表

def report(cfg, minutes):
    path = cfg["log"]
    if not os.path.exists(path):
        print("暂无日志:", path)
        return
    cutoff = (now_utc() - datetime.timedelta(minutes=minutes)).strftime("%Y-%m-%dT%H:%M:%SZ")
    evs = []
    with open(path) as f:
        for line in f:
            try:
                o = json.loads(line)
            except Exception:
                continue
            if o.get("ts", "") >= cutoff:
                evs.append(o)
    if not evs:
        print(f"最近 {minutes} 分钟无事件 —— 一切正常")
        return
    print(f"最近 {minutes} 分钟 ({len(evs)} 条):\n")
    for o in evs:
        ev = o["ev"]
        if ev == "cf_52x":
            tag = "  ← 非标端口·不告警" if o.get("noise") else ""
            print(f"  {o['ts']}  CF {o['status']}  {o['host']:32s} colo={o['colo']:4s} ×{o['count']}  [{o.get('origin','?')}]{tag}")
        elif ev == "probe_fail":
            print(f"  {o['ts']}  探针失败 {o['origin']} (第 {o['n']} 次) {o['err']}")
        elif ev == "origin_down":
            if o.get("suspect_path"):
                print(f"  {o['ts']}  🟡 疑似不可达 {o['origin']} "
                      f"— 本节点到「{o.get('region','?')}」整区失联, 未推运营群")
            else:
                print(f"  {o['ts']}  🔴 源站不可达 {o['origin']}")
        elif ev == "origin_up":
            mark = "🟡 疑似解除" if o.get("suspect_path") else "🟢 恢复"
            print(f"  {o['ts']}  {mark} {o['origin']} (持续 {o['down_sec']}s)")
        elif ev == "ops_notify_skip":
            print(f"  {o['ts']}  🚫 未发运营群恢复通知 {o['origin']} — {o['why']}")
        elif ev == "announce":
            print(f"  {o['ts']}  📢 接入说明 {o['alias']} -> {o['chat']} "
                  + ("已发送" if o["ok"] else f"失败: {o.get('err') or '原因未记录(旧版本)'}"))
        elif ev == "ops_notify":
            label = {"down": "异常·连不上", "app_down": "异常·页面报错", "up": "恢复"}.get(
                o["event"], o["event"])
            print(f"  {o['ts']}  📣 运营通知 {o['alias']} ({label}) -> {o['chat']} "
                  + ("成功" if o["ok"] else f"❌ 失败: {o.get('err') or '原因未记录(旧版本)'}"))
        elif ev == "confirm":
            mark = {"confirmed": "✅ 第二票确认", "denied": "🟡 第二票否决",
                    "unknown": "⏳ 未获第二票"}.get(o.get("verdict"), o.get("verdict"))
            print(f"  {o['ts']}  {mark} {o['origin']} [{o.get('kind')}]"
                  + (" (重问)" if o.get("retry") else "")
                  + (" 同区全失联" if o.get("suspect_region") else ""))
            for r in o.get("reasons") or []:
                print(f"           • {r}")
            if o.get("target"):
                print(f"           {fmt_target(o['target'])}")
        elif ev == "tg_fail":
            print(f"  {o['ts']}  ❌ 管理员通道发送失败 chat={o['chat']}: {o['err'][:80]}")
        elif ev == "ops_del":
            what = "私聊告警" if o.get("kind") == "admin" else "运营群消息"
            print(f"  {o['ts']}  🧹 撤回{what} chat={o['chat']} mid={o['mid']} "
                  + ("成功" if o["ok"] else f"失败: {str(o.get('err'))[:60]}"))
        elif ev == "ops_del_error":
            print(f"  {o['ts']}  ⚠ 撤回任务异常: {o['err'][:80]}")
        elif ev == "mtr_capture":
            print(f"  {o['ts']}  📍 路由快照 {o['origin']} — {o['reason']}")
            print(f"           判定: {o.get('verdict','?')}  "
                  f"TCP末跳丢包={o.get('tcp_loss')}%  ICMP末跳丢包={o.get('icmp_loss')}%")
            print(f"           {o['file']}")
        elif ev == "mtr_baseline":
            print(f"  {o['ts']}  路由基线已刷新 ({o['n']} 台)")
        elif ev == "zone_missing":
            print(f"  {o['ts']}  ⚠ 账户 {o['account']} 里找不到这些 zone: {', '.join(o['zones'])}")
        elif ev == "app_fail":
            print(f"  {o['ts']}  应用层失败 {o['origin']} (第 {o['n']} 次) {o['err']}")
        elif ev == "app_up":
            print(f"  {o['ts']}  🟢 应用层恢复 {o['origin']} (HTTP {o['code']})")
        elif ev == "cf_poll_error":
            print(f"  {o['ts']}  ⚠ CF 拉取失败 {o['account']}: {o['err'][:80]}")
        elif ev == "zones_auto_init":
            print(f"  {o['ts']}  🔄 轮询范围自动识别(基线): "
                  + " ".join(f"{k}={v}" for k, v in o["by_origin"].items()))
        elif ev == "zones_auto_change":
            print(f"  {o['ts']}  🔄 轮询范围自动更新")
            for ln in o["lines"]:
                print(f"           {ln}")
        elif ev == "zones_auto_error":
            print(f"  {o['ts']}  ⚠ 轮询范围识别失败 {o['account']}(沿用上次): {o['err'][:80]}")


def zones_preview(cfg):
    res = discover_zones(cfg)
    static = {}
    for o in cfg["origins"]:
        zs_cfg = o.get("zones") or {}
        for zs in (zs_cfg.values() if isinstance(zs_cfg, dict) else []):
            static.setdefault(o["name"], set()).update(zs)
    print(f"节点: {cfg.get('node')}  账户: {', '.join(a['name'] for a in cfg['accounts'])}")
    for on in sorted(set(res["by_origin"]) | set(static)):
        auto = set(res["by_origin"].get(on, []))
        old = static.get(on, set())
        print(f"\n{on}: 自动 {len(auto)} / 配置写死 {len(old)}"
              + ("  ✓ 一致" if auto == old else ""))
        if auto - old:
            print(f"  + 新增: {', '.join(sorted(auto - old))}")
        if old - auto:
            print(f"  - 移除: {', '.join(sorted(old - auto))}")
    for key, title in (("cf_only", "CF 橙云指向本机但 nginx 没绑(不轮询)"),
                       ("nginx_only", "nginx 绑了但 CF 完全没有记录指向本机")):
        if res[key]:
            print(f"\n⚠ {title}:")
            for on, zs in sorted(res[key].items()):
                print(f"  {on}: {', '.join(zs)}")
    if res["fallback"]:
        print("\n⚠ 退回只看 CF:", json.dumps(res["fallback"], ensure_ascii=False))
    if res["errors"]:
        print("\n⚠ 账户拉取失败:", json.dumps(res["errors"], ensure_ascii=False))


def main():
    args = sys.argv[1:]
    cfg = load_conf()
    if "--report" in args:
        i = args.index("--report")
        n = int(args[i + 1]) if len(args) > i + 1 and args[i + 1].isdigit() else 60
        return report(cfg, n)
    if "--announce-preview" in args:
        for n in (cfg.get("notify") or []):
            print("=" * 60)
            print(f"发往: {n.get('_群') or n.get('chats')}")
            print(ANNOUNCE_TPL.format(alias=n.get("alias", ""), domain=n.get("domain", ""),
                                      tz_name=n.get("tz_name", "本地"))
                  .replace("<b>", "").replace("</b>", ""))
        return
    if "--zones-preview" in args:
        return zones_preview(cfg)
    if "--announce-reset" in args:
        if os.path.exists(ANNOUNCE_STATE):
            os.remove(ANNOUNCE_STATE)
        print("已重置,下轮将向所有群重新发送接入说明")
        return
    if "--pending" in args:
        items = _load_pending()
        print(f"运营群 ops_msg_ttl_sec={cfg.get('ops_msg_ttl_sec', 3600)}  "
              f"私聊 admin_msg_ttl_sec={cfg.get('admin_msg_ttl_sec', 0)}  (0 = 不撤回)")
        if not items:
            print("待撤回队列为空")
            return
        now = time.time()
        print(f"待撤回 {len(items)} 条:")
        for it in items:
            left = int(it.get("sent", 0) + _item_ttl(cfg, it) - now)
            what = "私聊" if it.get("kind") == "admin" else "运营群"
            print(f"  {what:<4} chat={it['chat']:<16} mid={it['mid']:<8} "
                  + (f"{left // 3600} 时 {left % 3600 // 60} 分后撤回" if left > 0 else "已到期,下轮撤回"))
        return
    if "--sweep" in args:
        sweep_ephemeral(cfg)
        print("已处理到期消息, 队列剩余:", len(_load_pending()))
        return
    if "--chats" in args:
        tok = (cfg.get("telegram") or {}).get("token_file")
        token = open(tok).read().strip()
        with urllib.request.urlopen(
                f"https://api.telegram.org/bot{token}/getUpdates", timeout=20) as r:
            d = json.load(r)
        seen = {}
        for u in d.get("result") or []:
            m = (u.get("message") or u.get("channel_post")
                 or u.get("my_chat_member") or {})
            ch = m.get("chat") or {}
            if ch.get("id") and ch["id"] not in seen:
                seen[ch["id"]] = ch
                print(f"  chat_id={ch['id']:<16} type={ch.get('type'):<10} "
                      f"{ch.get('title') or ch.get('first_name') or ''}")
        if not seen:
            print("  没有消息 —— 先把 bot 拉进群并在群里发一条消息")
        return
    if "--baseline" in args:
        mtr_baseline(cfg)
        print("路由基线已刷新")
        return
    if "--mtr" in args:
        i = args.index("--mtr")
        name = args[i + 1] if len(args) > i + 1 else None
        o = next((x for x in cfg["origins"] if x["name"] == name), None)
        if not o:
            print("用法: --mtr <origin名>  可选: "
                  + ", ".join(x["name"] for x in cfg["origins"]))
            return 1
        _mtr_last.pop(name, None)
        mtr_capture(cfg, o, "手动抓取")
        return
    if "--test-tg" in args:
        ok, msg = tg_send(cfg, "✅ <b>site-manager 监控</b>\nTelegram 通道测试成功")
        print("发送成功" if ok else f"发送失败: {msg}")
        return 0 if ok else 1
    if "--peek-forced" in args:
        # 对端节点 authorized_keys 里 command= 锁到这里。只认 "peek <origin名>", 其他一律拒绝。
        orig = os.environ.get("SSH_ORIGINAL_COMMAND", "").split()
        if len(orig) != 2 or orig[0] != "peek":
            print(json.dumps({"error": "only 'peek <origin>' allowed"}))
            return 2
        o = next((x for x in cfg["origins"] if x["name"] == orig[1]), None)
        if not o:
            print(json.dumps({"error": f"unknown origin {orig[1][:32]}"}))
            return 2
        print(json.dumps(peek_origin(cfg, o), ensure_ascii=False))
        return
    if "--peek" in args:
        i = args.index("--peek")
        name = args[i + 1] if len(args) > i + 1 else None
        o = next((x for x in cfg["origins"] if x["name"] == name), None)
        if not o:
            print("用法: --peek <origin名>  可选: "
                  + ", ".join(x["name"] for x in cfg["origins"]))
            return 1
        print(json.dumps(peek_origin(cfg, o), ensure_ascii=False, indent=1))
        return
    run(cfg, once="--once" in args)


if __name__ == "__main__":
    sys.exit(main() or 0)
