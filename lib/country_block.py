#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Site Manager —— 全站国家访问控制（nginx http 级 allow/deny）

由 `site country-block ...` 调用。数据源：五大 RIR 官方 delegated 文件
（afrinic / apnic / arin / ripe / lacnic），按国家代码过滤、汇总去重后
生成 nginx 配置，写 /etc/nginx/conf.d/00-country-block.conf。

不依赖 nginx 的 geoip 模块，也不依赖 MaxMind/DB-IP 离线库。

用法（一般不用手调，走 site 命令）：
  country_block.py --out <conf> --state <dir> --mode block|allow \
                   --countries CN,US [--allow-ips 1.2.3.4/32,...] \
                   [--refresh] [--off] [--no-reload]

安全阀：
  * 每个请求的国家必须至少解析出 1 条 CIDR，否则中止（避免误清空拦截）
  * 写入前先备份旧文件；nginx -t 失败自动回滚，不 reload
"""
import argparse, fcntl, ipaddress, json, os, subprocess, sys, time, urllib.request

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
    """下载 RIR 数据，构建 needed 里每个国家的 CIDR；返回新的 countries dict。"""
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
            # 该国家没有任何数据：优先沿用旧缓存
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


def render(countries, mode, allow_ips, logfile):
    lines = [
        '# ===== 自动生成，请勿手改（由 site country-block 维护）=====',
        '# Site Manager 全站国家访问控制：nginx http 级 allow/deny，对所有站点/新站点生效',
        '# 配置: /opt/site_manager/config/country_block.conf',
        '# 生成时间: %s  模式: %s  国家: %s' % (
            time.strftime('%Y-%m-%d %H:%M:%S'), mode, ' '.join(countries) or '(none)'),
        '# 注意: 本文件不能包含 listen 指令（会抢走 nginx socket 属主）',
    ]
    total = 0
    for ip in allow_ips:
        lines.append('allow %s;' % ip)
    if mode == 'allow':
        for cc in countries:
            for net in countries[cc]:
                lines.append('allow %s;' % net)
                total += 1
        lines.append('deny all;')
    else:
        for cc in countries:
            for net in countries[cc]:
                lines.append('deny %s;' % net)
                total += 1
    return '\n'.join(lines) + '\n', total


def normalize(text):
    return '\n'.join(l.strip() for l in text.splitlines()
                     if l.strip() and not l.lstrip().startswith('#'))


def nginx_test():
    return subprocess.run([NGINX_BIN, '-t'], capture_output=True, text=True)


def apply_conf(path, text, reload_nginx, logfile):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    old = None
    if os.path.exists(path):
        with open(path) as f:
            old = f.read()
    if old is not None and normalize(old) == normalize(text):
        log('apply: 无变化（%s）' % path, logfile)
        return 'unchanged'
    tmp = path + '.tmp'
    with open(tmp, 'w') as f:
        f.write(text)
    os.chmod(tmp, 0o644)
    os.replace(tmp, path)
    r = nginx_test()
    if r.returncode != 0:
        log('nginx -t 失败，回滚: ' + (r.stderr or '')[-400:], logfile)
        if old is not None:
            with open(path, 'w') as f:
                f.write(old)
        else:
            os.unlink(path)
        return 'failed'
    if reload_nginx:
        subprocess.run([SYSTEMCTL_BIN, 'reload', 'nginx'], capture_output=True)
        log('apply: 已写入并 reload nginx（%s）' % path, logfile)
        return 'reloaded'
    log('apply: 已写入（未 reload）（%s）' % path, logfile)
    return 'written'


def disable(path, reload_nginx, logfile):
    if os.path.exists(path):
        os.unlink(path)
        r = nginx_test()
        if r.returncode != 0:
            log('删除后 nginx -t 失败，请人工检查: ' + (r.stderr or '')[-300:], logfile)
            return 'failed'
        if reload_nginx:
            subprocess.run([SYSTEMCTL_BIN, 'reload', 'nginx'], capture_output=True)
        log('已关闭并删除 %s' % path, logfile)
        return 'removed'
    log('已关闭（文件不存在: %s）' % path, logfile)
    return 'absent'


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--out', required=True)
    ap.add_argument('--state', required=True)
    ap.add_argument('--mode', default='block', choices=['block', 'allow'])
    ap.add_argument('--countries', default='')
    ap.add_argument('--allow-ips', default='')
    ap.add_argument('--refresh', action='store_true')
    ap.add_argument('--off', action='store_true')
    ap.add_argument('--no-reload', action='store_true')
    ap.add_argument('--log', default='/var/log/country-block.log')
    a = ap.parse_args()

    reload_nginx = not a.no_reload
    if a.off:
        return 0 if disable(a.out, reload_nginx, a.log) in ('removed', 'absent') else 1

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
    lock_path = os.path.join(a.state, '.lock')
    lk = open(lock_path, 'w')
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
    text, total = render(selected, a.mode, allow_ips, a.log)
    log('渲染: mode=%s countries=%s cidrs=%d' % (a.mode, ' '.join(countries), total), a.log)
    status = apply_conf(a.out, text, reload_nginx, a.log)
    return 0 if status in ('unchanged', 'reloaded', 'written') else 1


if __name__ == '__main__':
    sys.exit(main())
