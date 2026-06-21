# Ubuntu 24.04 基礎設定一鍵部署

`setup.sh` 整合了新建 VM 後常用的基礎安全與環境設定：

- `apt update` / `dist-upgrade`
- 自動安全性更新（`unattended-upgrades` + `20auto-upgrades`，僅安全性來源）
- SSH 強化（自訂 Port、禁止 root 登入、限制 `AllowUsers`）
- UFW 防火牆（開放 SSH 埠 + 80/443，可自訂）
- Fail2Ban 入侵防護（含 `ignoreip` 白名單）
- Chrony NTP 時間同步（可指定內網 NTP server）、時區設定為 `Asia/Taipei`
- QEMU Guest Agent（適用於 KVM/Proxmox 等虛擬化平台）
- `net-tools` 等常用套件安裝

## 直接從 GitHub 下載並執行

```bash
curl -fsSL https://raw.githubusercontent.com/oupaul/Ubuntu-Setting/main/setup.sh | sudo bash
```

## 自訂參數（環境變數）

腳本所有可調整項目皆透過環境變數帶入，預設值如下：

| 變數 | 預設值 | 說明 |
|---|---|---|
| `SSH_PORT` | `22` | SSH 監聽埠 |
| `USERNAME` | `itadmin` | 允許 SSH 登入的使用者（請確保此帳號已存在且已設定金鑰） |
| `NTP_SERVER` | 空（使用 Ubuntu 預設 pool） | 內網 NTP server IP/主機名 |
| `TIMEZONE` | `Asia/Taipei` | 系統時區 |
| `ALLOW_TCP_PORTS` | `80,443` | 除了 SSH 之外要開放的 TCP 埠（逗號分隔） |
| `IGNORE_IPS` | `127.0.0.1/8` | Fail2Ban 白名單 IP/CIDR（空白分隔） |
| `SKIP_DIST_UPGRADE` | `0` | 設為 `1` 可跳過最後的 `dist-upgrade` |

範例：

```bash
curl -fsSL https://raw.githubusercontent.com/oupaul/Ubuntu-Setting/main/setup.sh -o setup.sh
sudo SSH_PORT=2589 USERNAME=itadmin NTP_SERVER=192.0.2.1 \
  IGNORE_IPS="192.0.2.0/24 198.51.100.0/24" bash setup.sh
```

## 注意事項

1. **務必先確認 `USERNAME` 對應的帳號已存在並設定好 SSH 金鑰登入**，否則修改 `AllowUsers` 後可能無法以該帳號登入。執行前可先用既有連線測試新埠是否可登入，再關閉舊連線，避免被鎖在外面。
2. 若變更了 `SSH_PORT`，記得在防火牆/安全群組（如雲端供應商的 Security Group）一併放行新埠。
3. 腳本會備份 `sshd_config` 與 `chrony.conf` 至同目錄下的 `.bak.<timestamp>` 檔案。
4. 執行完成後建議 `sudo reboot` 套用所有變更。
