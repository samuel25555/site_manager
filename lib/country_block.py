#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Site Manager —— 全站国家访问控制（nginx http 级 geo + server 级 return）

由 `site country-block ...` 调用。数据源：五大 RIR 官方 delegated 文件
（afrinic / apnic / arin / ripe / lacnic），按国家代码过滤、汇总去重。

生成两个文件：
  /etc/nginx/conf.d/00-country-block.conf         geo $country_blocked { ... }   (http 级)
  /etc/nginx/snippets/country-block-guard.conf    if ($country_blocked) { return 444; }

并在 /www/vhost/nginx/* 的每个 server 块里确保有 include 守卫片段，
这样 444 才会在 server 上下文生效（nginx 的 http 级不能直接 return）。

为什么不用 deny：
  deny 只能返回 403，而且返回体是 nginx 默认 403 页；要 444（直接断连、无响应）
  必须在 server/location 里 return。geo 变量 + 每个 server include 一次即可，
  新增站点由 site create 模板带入，apply 时也会自动补齐遗漏的 vhost。

安全阀：
  * 每个请求的国家必须至少解析出 1 条 CIDR，否则中止
  * 修改任何文件前先备份；nginx -t 失败全部回滚，不 reload
"""
import argparse, fcntl, ipaddress, json, os, re, subprocess, sys, time, urllib.request

RIR = {
    'afrinic': 'https://ftp.afrinic.net/pub/stats/afrinic/delegated-afrinic-latest',
    'apnic':   'https://ftp.apnic.net/stats/apnic/delegated-apnic-latest',
    'arin':    'https://ftp.arin.net/pub/stats/arin/delegated-arin-extended-latest',
    'ripe':    'https://ftp.ripe.net/pub/stats/ripencc/delegated-ripencc-latest',
    'lacnic':  'https://ftp.lacnic.net/pub/stats/lacnic/delegated-lacnic-latest',
}

CACHE_MAX_AGE = 7 * 86400
NGINX_BIN = '/usr/sbin/nginx' if os.path.exists('/usr/sbin/nginx') else 'nginx'
SYSTEMCTL_BIN = '/bin/systemctl' if os.path.exists('/bin/systemctl') else '/usr/bin/systemctl'
INCLUDE_LINE = '    include /etc/nginx/snippets/country-block-guard.conf;  # [country-block]'
SERVER_RE = re.compile(r'^\s*server\s*\{')


def log(msg, logfile=None):
    line = time.strftime('%Y-%m-%d %H:%M:%S ') + msg
    print(line, flush=True)
    if logfile:
        try:
            with open(logfile, 'a') as f:
                f.write(line + '\n')
        except OSError:
            pass


def fetch(url):
    req = urllib.request.Request(url, headers={'User-Agent': 'site_manager-country-block/1.0'})
    with urllib.request.urlopen(req, timeout=180) as r:
        return r.read().decode('utf-8', 'replace')


def build_countries(needed, cache, logfile):
    acc = {cc: {'v4': [], 'v6': []} for cc in needed}
    ok_rir = 0
    for name, url in RIR.items():
        try:
            text = fetch(url)
            ok_rir += 1
        except Exception as e:
            log('refresh: %s download failed: %s' % (name, e), logfile)
            continue
        n = 0
        for line in text.splitlines():
            if not line or line.startswith('#'):
                continue
            p = line.split('|')
            if len(p) < 7:
                continue
            cc, typ, start, val, status = p[1], p[2], p[3], p[4], p[6]
            if cc not in acc or status not in ('allocated', 'assigned'):
                continue
            try:
                if typ == 'ipv4':
                    cnt = int(val)
                    s = int(ipaddress.IPv4Address(start))
                    acc[cc]['v4'].extend(ipaddress.summarize_address_range(
                        ipaddress.IPv4Address(s), ipaddress.IPv4Address(s + cnt - 1)))
                elif typ == 'ipv6':
                    acc[cc]['v6'].append(ipaddress.IPv6Network('%s/%s' % (start, int(val)), strict=False))
            except Exception:
                continue
            n += 1
        log('refresh: %s parsed %d records' % (name, n), logfile)

    if ok_rir == 0:
        raise RuntimeError('所有 RIR 数据源都下载失败')

    res = {}
    for cc, d in acc.items():
        merged = list(ipaddress.collapse_addresses(d['v4'])) + list(ipaddress.collapse_addresses(d['v6']))
        res[cc] = [str(x) for x in merged]
        if not res[cc]:
            old = (cache.get('countries') or {}).get(cc)
            if old:
                log('refresh: %s 无新数据，沿用缓存（%d 条）' % (cc, len(old)), logfile)
                res[cc] = old
            else:
                raise RuntimeError('国家 %s 没有解析到任何 CIDR（代码错误或数据源异常）' % cc)
        log('refresh: %s -> %d cidrs' % (cc, len(res[cc])), logfile)
    return res


def load_cache(path):
    try:
        with open(path) as f:
            return json.load(f)
    except Exception:
        return {'updated': 0, 'countries': {}}


def render_map(countries, mode, allow_ips, http_status, logfile):
    lines = [
        '# ===== 自动生成，请勿手改（由 site country-block 维护）=====',
        '# Site Manager 全站国家访问控制：http 级 geo 变量，配合每个 server 里的',
        '#   include /etc/nginx/snippets/country-block-guard.conf',
        '# 配置: /opt/site_manager/config/country_block.conf',
        '# 生成时间: %s  模式: %s  国家: %s  响应: %s' % (
            time.strftime('%Y-%m-%d %H:%M:%S'), mode, ' '.join(countries) or '(none)', http_status),
        '# 注意: 本文件不能包含 listen 指令（会抢走 nginx socket 属主）',
        'geo $country_blocked {',
        '    default %d;' % (0 if mode == 'block' else 1),
    ]
    total = 0
    for ip in allow_ips:
        lines.append('    %s 0;' % ip)
    flag = 1 if mode == 'block' else 0
    for cc in countries:
        for net in countries[cc]:
            lines.append('    %s %d;' % (net, flag))
            total += 1
    lines.append('}')
    return '\n'.join(lines) + '\n', total


def render_guard(http_status):
    return (
        '# ===== 自动生成，请勿手改（由 site country-block 维护）=====\n'
        '# 命中被拦国家时直接关闭连接，不返回任何内容\n'
        'if ($country_blocked) {\n'
        '    return %s;\n'
        '}\n' % http_status
    )

DISABLED_GUARD = (
    '# ===== 自动生成，请勿手改（由 site country-block 维护）=====\n'
    '# country-block 已停用\n'
)


def normalize(text):
    return '\n'.join(l.strip() for l in text.splitlines()
                     if l.strip() and not l.lstrip().startswith('#'))


def nginx_test():
    return subprocess.run([NGINX_BIN, '-t'], capture_output=True, text=True)


def ensure_vhost_includes(vhost_dir, logfile):
    """在每个 server 块后补 include。返回 (modified dict path->old_text, total_servers)."""
    modified, servers = {}, 0
    if not os.path.isdir(vhost_dir):
        return modified, 0
    for name in sorted(os.listdir(vhost_dir)):
        if '.bak' in name or name.startswith('.'):
            continue
        path = os.path.join(vhost_dir, name)
        if not os.path.isfile(path):
            continue
        try:
            with open(path) as f:
                text = f.read()
        except OSError:
            continue
        lines = text.splitlines(keepends=True)
        out, changed = [], False
        for i, line in enumerate(lines):
            out.append(line)
            if SERVER_RE.match(line):
                servers += 1
                window = ''.join(lines[i + 1:i + 4])
                if 'country-block-guard.conf' not in window:
                    if not line.endswith('\n'):
                        out[-1] = line + '\n'
                    out.append(INCLUDE_LINE + '\n')
                    changed = True
        if changed:
            modified[path] = text
            with open(path, 'w') as f:
                f.write(''.join(out))
            log('vhost: 已补 include %s' % path, logfile)
    return modified, servers


def restore(paths):
    for path, text in paths.items():
        try:
            with open(path, 'w') as f:
                f.write(text)
        except OSError:
            pass


def write_file(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'w') as f:
        f.write(text)
    os.chmod(path, 0o644)


def apply_all(args, countries, mode, allow_ips, logfile):
    map_text, total = render_map(countries, mode, allow_ips, args.http_status, logfile)
    guard_text = render_guard(args.http_status)
    log('渲染: mode=%s countries=%s cidrs=%d status=%s' % (
        mode, ' '.join(countries), total, args.http_status), logfile)

    # 记录旧内容用于回滚
    backups = {}
    for p in (args.out, args.snippet):
        if os.path.exists(p):
            with open(p) as f:
                backups[p] = f.read()

    vhost_backups, servers = ensure_vhost_includes(args.vhost_dir, logfile)
    write_file(args.out, map_text)
    write_file(args.snippet, guard_text)

    r = nginx_test()
    if r.returncode != 0:
        log('nginx -t 失败，回滚: ' + (r.stderr or '')[-500:], logfile)
        restore(vhost_backups)
        for p, old in backups.items():
            with open(p, 'w') as f:
                f.write(old)
        for p in (args.out, args.snippet):
            if p not in backups and os.path.exists(p):
                os.unlink(p)
        return 'failed'

    if args.no_reload:
        log('apply: 已写入（未 reload）', logfile)
        return 'written'
    subprocess.run([SYSTEMCTL_BIN, 'reload', 'nginx'], capture_output=True)
    log('apply: 已写入并 reload nginx（server 块 %d 个，vhost 补 include %d 处）' % (
        servers, len(vhost_backups)), logfile)
    try:
        os.makedirs(args.state, exist_ok=True)
        with open(os.path.join(args.state, 'last-good.conf'), 'w') as f:
            f.write(map_text)
    except OSError:
        pass
    return 'reloaded'


def disable(args, logfile):
    # 保留空守卫文件，避免 vhost 里的 include 失效
    if os.path.exists(args.out):
        os.unlink(args.out)
    write_file(args.snippet, DISABLED_GUARD)
    r = nginx_test()
    if r.returncode != 0:
        log('停用后 nginx -t 失败，请人工检查: ' + (r.stderr or '')[-400:], logfile)
        return 'failed'
    if not args.no_reload:
        subprocess.run([SYSTEMCTL_BIN, 'reload', 'nginx'], capture_output=True)
    log('已停用（删除 geo 表，守卫改为空）', logfile)
    return 'disabled'


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--out', default='/etc/nginx/conf.d/00-country-block.conf')
    ap.add_argument('--snippet', default='/etc/nginx/snippets/country-block-guard.conf')
    ap.add_argument('--vhost-dir', default='/www/vhost/nginx')
    ap.add_argument('--state', required=True)
    ap.add_argument('--mode', default='block', choices=['block', 'allow'])
    ap.add_argument('--countries', default='')
    ap.add_argument('--allow-ips', default='')
    ap.add_argument('--http-status', default='444')
    ap.add_argument('--refresh', action='store_true')
    ap.add_argument('--off', action='store_true')
    ap.add_argument('--no-reload', action='store_true')
    ap.add_argument('--log', default='/var/log/country-block.log')
    a = ap.parse_args()
    a.http_status = str(a.http_status)
    if a.http_status not in ('444', '403', '410', '404'):
        log('错误: http-status 只支持 444/403/410/404', a.log)
        return 2

    if a.off:
        return 0 if disable(a, a.log) in ('disabled',) else 1

    countries = [c.strip().upper() for c in a.countries.split(',') if c.strip()]
    allow_ips = [x.strip() for x in a.allow_ips.split(',') if x.strip()]
    if not countries:
        log('错误: 国家列表为空（先 site country-block set CN ...）', a.log)
        return 2
    for cc in countries:
        if len(cc) != 2 or not cc.isalpha():
            log('错误: 无效国家代码 %s（需 ISO 3166-1 两位，如 CN/US/JP）' % cc, a.log)
            return 2
    for ip in allow_ips:
        try:
            ipaddress.ip_network(ip, strict=False)
        except ValueError:
            log('错误: 无效 IP/CIDR %s' % ip, a.log)
            return 2

    os.makedirs(a.state, exist_ok=True)
    lk = open(os.path.join(a.state, '.lock'), 'w')
    try:
        fcntl.flock(lk, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        log('另一个实例正在运行，退出', a.log)
        return 0

    cache_path = os.path.join(a.state, 'countries.json')
    cache = load_cache(cache_path)
    have = cache.get('countries') or {}
    missing = [c for c in countries if c not in have]
    stale = (time.time() - cache.get('updated', 0)) > CACHE_MAX_AGE
    if a.refresh or missing or stale:
        log('同步 %s（missing=%s stale=%s）' % (' '.join(countries), missing, stale), a.log)
        try:
            fresh = build_countries(countries, cache, a.log)
        except Exception as e:
            log('构建失败: %s（保留现有配置）' % e, a.log)
            return 1
        have.update(fresh)
        cache = {'updated': int(time.time()), 'countries': have}
        tmp = cache_path + '.tmp'
        with open(tmp, 'w') as f:
            json.dump(cache, f, separators=(',', ':'))
        os.replace(tmp, cache_path)
    else:
        log('使用缓存（%d 小时前更新）' % int((time.time() - cache.get('updated', 0)) / 3600), a.log)

    selected = {cc: have[cc] for cc in countries}
    status = apply_all(a, selected, a.mode, allow_ips, a.log)
    return 0 if status in ('reloaded', 'written', 'unchanged') else 1


if __name__ == '__main__':
    sys.exit(main())
