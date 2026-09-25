#!/bin/bash
#===============================================================================
# dev(本机=FTP服务器/管理中枢) 自身命脉数据备份
# 直接落到 /data/backup/data_other_backup/DEV1/infra/(由 sync_mirror.sh 镜像到 mru 异地；jp-win 的 sync_jp.sh 并行到 2026-11-01)
# dev 无需 FTP 回环:它就是 FTP 服务器本机。
#===============================================================================
set -euo pipefail
DEST=/data/backup/data_other_backup/DEV1/infra
KEEP=14
TS=$(date +%Y-%m-%d_%H-%M-%S)
mkdir -p "$DEST"
OUT="$DEST/dev_infra_${TS}.tar.gz"

# 命脉:全机队 DNS/SSL/监控配置+token、CF/NameSilo 凭据与工具、机队访问密钥
# 排除可再生的截图/日志/缓存/大归档
tar czf "$OUT" \
  --exclude='*/h5_screenshots' --exclude='*/vt_screenshots' --exclude='*/vt_screenshots_h5' \
  --exclude='*/archive' --exclude='*/logs' --exclude='*/__pycache__' \
  --exclude='*/.venv' --exclude='*/pyenv' --exclude='*.7z' --exclude='*.jsonl' \
  /opt/site_manager/config \
  /opt/projects/other/cloudflare_dns \
  /root/.ssh/config /root/.ssh/id_ed25519 /root/.ssh/id_ed25519.pub /root/.ssh/id_fleet_ed25519 /root/.ssh/id_fleet_ed25519.pub /root/.ssh/github_ed25519 \
  /root/.claude/skills /root/.claude/settings.json /root/.claude/hooks /root/.claude/projects /root/tools \
  2>/dev/null || true

# 保留最近 KEEP 份
ls -1t "$DEST"/dev_infra_*.tar.gz 2>/dev/null | tail -n +$((KEEP+1)) | xargs -r rm -f

echo "$(date '+%F %T') dev_infra 备份完成: $OUT ($(du -h "$OUT"|cut -f1))"
