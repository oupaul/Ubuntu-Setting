#!/usr/bin/env bash
#
# Ubuntu 24.04 VM 基礎設定一鍵部署腳本
#
# 用法（直接從 GitHub 下載並執行）：
#   curl -fsSL https://raw.githubusercontent.com/<user>/<repo>/<branch>/setup.sh | sudo bash
#
# 或先下載再以參數客製化：
#   wget https://raw.githubusercontent.com/<user>/<repo>/<branch>/setup.sh
#   sudo SSH_PORT=2589 USERNAME=itadmin NTP_SERVER=192.0.2.1 bash setup.sh
#
# 可透過環境變數覆寫的設定值見下方「變數」區塊。
set -euo pipefail

# ===================== 變數（可用環境變數覆寫） =====================
SSH_PORT="${SSH_PORT:-22}"
USERNAME="${USERNAME:-itadmin}"
NTP_SERVER="${NTP_SERVER:-}"          # 留空則使用 Ubuntu 預設 NTP pool
TIMEZONE="${TIMEZONE:-Asia/Taipei}"
ALLOW_TCP_PORTS="${ALLOW_TCP_PORTS:-80,443}"   # 除了 SSH_PORT 之外要開放的 TCP 埠
IGNORE_IPS="${IGNORE_IPS:-127.0.0.1/8}"        # fail2ban 白名單，多個用空白分隔
SKIP_DIST_UPGRADE="${SKIP_DIST_UPGRADE:-0}"    # 設為 1 可跳過最後的 dist-upgrade + reboot 提示

if [[ "$(id -u)" -ne 0 ]]; then
  echo "請使用 root 權限執行（例如：sudo bash setup.sh 或透過 curl | sudo bash）" >&2
  exit 1
fi

log() { echo -e "\n==> $*"; }

export DEBIAN_FRONTEND=noninteractive

# ===================== 1. 系統更新 =====================
log "更新套件清單..."
apt update

# 避免 dpkg 鎖死在未完成的設定
dpkg --configure -a || true

# ===================== 2. 安裝必要套件 =====================
log "安裝必要套件 (net-tools, chrony, fail2ban, qemu-guest-agent, unattended-upgrades, ufw)..."
apt install -y net-tools chrony fail2ban qemu-guest-agent unattended-upgrades ufw software-properties-common

# ===================== 3. 設定自動安全性更新 =====================
log "設定 unattended-upgrades（僅安全性更新）..."
cat > /etc/apt/apt.conf.d/50unattended-upgrades <<'EOF'
Unattended-Upgrade::Allowed-Origins {
//      "${distro_id}:${distro_codename}";
        "${distro_id}:${distro_codename}-security";
        "${distro_id}ESMApps:${distro_codename}-apps-security";
        "${distro_id}ESM:${distro_codename}-infra-security";
//      "${distro_id}:${distro_codename}-updates";
//      "${distro_id}:${distro_codename}-proposed";
//      "${distro_id}:${distro_codename}-backports";
};
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot "false";
EOF

cat > /etc/apt/apt.conf.d/20auto-upgrades <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Download-Upgradeable-Packages "1";
APT::Periodic::AutocleanInterval "7";
APT::Periodic::Unattended-Upgrade "1";
EOF

# ===================== 4. SSH 強化設定 =====================
log "設定 SSH（Port=${SSH_PORT}, AllowUsers=${USERNAME}, PermitRootLogin=no）..."
SSHD_CONFIG="/etc/ssh/sshd_config"
cp "$SSHD_CONFIG" "${SSHD_CONFIG}.bak.$(date +%Y%m%d%H%M%S)"

if grep -qE '^[#[:space:]]*Port[[:space:]]' "$SSHD_CONFIG"; then
  sed -i "s/^[#[:space:]]*Port[[:space:]].*/Port ${SSH_PORT}/" "$SSHD_CONFIG"
else
  echo "Port ${SSH_PORT}" >> "$SSHD_CONFIG"
fi

if grep -qE '^[#[:space:]]*PermitRootLogin[[:space:]]' "$SSHD_CONFIG"; then
  sed -i "s/^[#[:space:]]*PermitRootLogin[[:space:]].*/PermitRootLogin no/" "$SSHD_CONFIG"
else
  echo "PermitRootLogin no" >> "$SSHD_CONFIG"
fi

if ! grep -q "^AllowUsers ${USERNAME}\$" "$SSHD_CONFIG"; then
  echo "AllowUsers ${USERNAME}" >> "$SSHD_CONFIG"
fi

sshd -t -f "$SSHD_CONFIG"
systemctl restart ssh

# ===================== 5. UFW 防火牆 =====================
log "設定 UFW 防火牆..."
ufw allow "${SSH_PORT}/tcp"
IFS=',' read -ra PORTS <<< "$ALLOW_TCP_PORTS"
for p in "${PORTS[@]}"; do
  [[ -n "$p" ]] && ufw allow "${p}/tcp"
done
ufw --force enable

# ===================== 6. Fail2Ban =====================
log "設定 Fail2Ban..."
if [[ ! -f /etc/fail2ban/jail.local ]]; then
  cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local
fi

cat > /etc/fail2ban/jail.d/local-overrides.conf <<EOF
[DEFAULT]
ignoreip = ${IGNORE_IPS}
bantime  = 1h
findtime = 10m
maxretry = 5

[sshd]
enabled  = true
port     = ${SSH_PORT}
filter   = sshd
logpath  = /var/log/auth.log
maxretry = 3
bantime  = 24h
EOF

systemctl enable fail2ban
systemctl restart fail2ban

# ===================== 7. Chrony 時間同步 =====================
log "設定 Chrony NTP..."
if [[ -n "$NTP_SERVER" ]]; then
  cp /etc/chrony/chrony.conf /etc/chrony/chrony.conf.bak.$(date +%Y%m%d%H%M%S)
  sed -i -E 's/^(pool .*)/#\1/' /etc/chrony/chrony.conf
  if ! grep -q "^server ${NTP_SERVER}" /etc/chrony/chrony.conf; then
    echo "server ${NTP_SERVER} iburst" >> /etc/chrony/chrony.conf
  fi
fi
systemctl restart chrony

log "設定時區與本地 RTC..."
timedatectl set-timezone "$TIMEZONE"
timedatectl set-local-rtc 1 --adjust-system-clock || true

# ===================== 8. QEMU Guest Agent =====================
log "啟用 QEMU Guest Agent..."
systemctl enable --now qemu-guest-agent

# ===================== 9. 系統升級 =====================
if [[ "$SKIP_DIST_UPGRADE" != "1" ]]; then
  log "執行 apt dist-upgrade..."
  apt dist-upgrade -y
  apt autoremove -y
fi

log "完成！摘要："
echo "  SSH Port        : ${SSH_PORT}"
echo "  允許登入使用者   : ${USERNAME}（請確認該帳號已存在並設定好金鑰）"
echo "  時區            : ${TIMEZONE}"
echo "  Fail2Ban 白名單  : ${IGNORE_IPS}"
echo "  開放 TCP 埠      : ${SSH_PORT},${ALLOW_TCP_PORTS}"
echo
echo "若有套件需要重新啟動服務，請檢查並執行：sudo reboot"
