#!/bin/bash
# CentOS 7/8/Stream environment
# 2026-10-30
# longxiang.zhu83@gmail.com

COLOR_ERROR="\e[38;5;198m"
COLOR_NONE="\e[0m"
COLOR_SUCC="\e[92m"

require_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo -e "${COLOR_ERROR}请使用 root 用户运行此脚本。${COLOR_NONE}"
        exit 1
    fi
}

install_packages() {
    if command -v dnf >/dev/null 2>&1; then
        dnf install -y "$@"
    else
        yum install -y "$@"
    fi
}

update_core(){
    echo -e "${COLOR_ERROR}当前系统内核版本太低 <${VERSION_CURR}>，请升级内核后再启用 BBR。${COLOR_NONE}"
    echo "CentOS 的内核升级方式因版本及启用的软件源而异，请参考发行版文档；完成升级并重启后重新运行本脚本。"
}

check_bbr(){
    if lsmod | grep -q bbr; then
        echo -e "${COLOR_SUCC}TCP BBR 拥塞控制算法已经启动${COLOR_NONE}"
    else
        start_bbr
    fi
}

start_bbr(){
    echo "启动 TCP BBR 拥塞控制算法"
    modprobe tcp_bbr || return 1
    install -d /etc/modules-load.d
    grep -qxF tcp_bbr /etc/modules-load.d/modules.conf 2>/dev/null || echo tcp_bbr >> /etc/modules-load.d/modules.conf
    cat >/etc/sysctl.d/99-bbr.conf <<'EOF'
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
EOF
    sysctl --system
    sysctl net.ipv4.tcp_available_congestion_control
    sysctl net.ipv4.tcp_congestion_control
}

install_bbr() {
    if [[ "$(printf '%s\n' "$VERSION_MIN" "$VERSION_CURR" | sort -V | head -n1)" == "$VERSION_MIN" ]]; then
        check_bbr
    else
        update_core
    fi
}

install_docker() {
    if ! command -v docker >/dev/null 2>&1; then
        echo "开始安装 Docker CE"
        install_packages yum-utils device-mapper-persistent-data lvm2
        yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo || return 1
        install_packages docker-ce docker-ce-cli containerd.io
        systemctl enable --now docker
    else
        echo -e "${COLOR_SUCC}Docker 已经安装${COLOR_NONE}"
        systemctl enable --now docker
    fi
}

check_container(){
    docker ps --format '{{.Names}}' | grep -q "$1"
}

install_certbot() {
    echo "开始安装 certbot 命令行工具"
    if grep -qi 'Oracle Linux' /etc/os-release 2>/dev/null || grep -qi 'Oracle Linux' /etc/redhat-release 2>/dev/null; then
        # Oracle Linux 9 ships Certbot in its developer EPEL repository.
        install_packages oracle-epel-release-el9 || return 1
        if command -v dnf >/dev/null 2>&1; then
            dnf config-manager --set-enabled ol9_developer_EPEL || return 1
        else
            yum-config-manager --enable ol9_developer_EPEL || return 1
        fi
    else
        install_packages epel-release || return 1
    fi
    if command -v dnf >/dev/null 2>&1; then dnf makecache; else yum makecache; fi
    install_packages certbot
}

create_cert() {
    if ! command -v certbot >/dev/null 2>&1; then install_certbot || return 1; fi
    echo "开始生成 SSL 证书"
    echo -e "${COLOR_ERROR}注意：生成证书前，需要将域名指向一个有效的 IP。${COLOR_NONE}"
    read -r -p "是否已经将域名指向了 IP？[Y/n] " has_record
    if [[ ! "$has_record" =~ ^([Yy]|)$ ]]; then echo "请操作完成后再继续。"; return; fi
    read -r -p "请输入你要使用的域名: " domain
    certbot certonly --standalone -d "$domain"
}

install_gost() {
    if ! command -v docker >/dev/null 2>&1; then echo -e "${COLOR_ERROR}未发现 Docker，请先安装 Docker。${COLOR_NONE}"; return; fi
    if check_container gost; then echo -e "${COLOR_ERROR}Gost 容器已经在运行，请先手动停止并删除。${COLOR_NONE}"; return; fi
    echo "准备启动 Gost 代理程序。"
    read -r -p "请输入你要使用的域名：" DOMAIN
    read -r -p "请输入你要使用的用户名: " USER
    read -r -p "请输入你要使用的密码: " PASS
    read -r -p "请输入 HTTP/2 侦听端口(443)：" PORT
    if ! [[ "$PORT" =~ ^[0-9]+$ ]] || (( PORT < 1 || PORT > 65535 )); then PORT=443; fi
    CERT_DIR=/etc/letsencrypt
    CERT=${CERT_DIR}/live/${DOMAIN}/fullchain.pem
    KEY=${CERT_DIR}/live/${DOMAIN}/privkey.pem
    docker run -d --name gost -v "${CERT_DIR}:${CERT_DIR}:ro" --net=host ginuerzh/gost \
        -L "http2://${USER}:${PASS}@0.0.0.0:${PORT}?cert=${CERT}&key=${KEY}&probe_resist=code:400&knock=www.google.com"
}

crontab_exists() { crontab -l 2>/dev/null | grep -Fq "$1"; }

create_cron_job(){
    (crontab -l 2>/dev/null; echo '0 0 1 * * /usr/bin/certbot renew --force-renewal') | awk '!seen[$0]++' | crontab -
    (crontab -l 2>/dev/null; echo '5 0 1 * * /usr/bin/docker restart gost') | awk '!seen[$0]++' | crontab -
    systemctl enable --now crond
    echo -e "${COLOR_SUCC}证书更新及 Gost 重启定时任务已配置。${COLOR_NONE}"
}

install_shadowsocks(){
    if ! command -v docker >/dev/null 2>&1; then echo -e "${COLOR_ERROR}未发现 Docker，请先安装 Docker。${COLOR_NONE}"; return; fi
    if check_container ss; then echo -e "${COLOR_ERROR}ShadowSocks 容器已经在运行，请先手动停止并删除。${COLOR_NONE}"; return; fi
    read -r -p "请输入你要使用的密码: " PASS
    read -r -p "请输入 ShadowSocks 侦听端口(1984)：" PORT
    if ! [[ "$PORT" =~ ^[0-9]+$ ]] || (( PORT < 1 || PORT > 65535 )); then PORT=1984; fi
    docker run -dt --name ss -p "${PORT}:${PORT}" mritd/shadowsocks \
        -s "-s 0.0.0.0 -p ${PORT} -m aes-256-cfb -k ${PASS} --fast-open"
}

install_vpn(){
    if ! command -v docker >/dev/null 2>&1; then echo -e "${COLOR_ERROR}未发现 Docker，请先安装 Docker。${COLOR_NONE}"; return; fi
    if check_container vpn; then echo -e "${COLOR_ERROR}VPN 容器已经在运行，请先手动停止并删除。${COLOR_NONE}"; return; fi
    read -r -p "请输入你要使用的用户名: " USER
    read -r -p "请输入你要使用的密码: " PASS
    read -r -p "请输入你要使用的 PSK Key: " PSK
    docker run -d --name vpn --privileged -e PSK="$PSK" -e USERNAME="$USER" -e PASSWORD="$PASS" \
        -p 500:500/udp -p 4500:4500/udp -p 1701:1701/tcp -p 1194:1194/udp siomiz/softethervpn
}

install_brook(){
    brook_file=/usr/local/brook/brook
    [[ -e "$brook_file" ]] && echo -e "${COLOR_ERROR}Brook 已经安装，请检查!${COLOR_NONE}" && return
    install_packages wget
    wget -N --no-check-certificate https://raw.githubusercontent.com/ToyoDAdoubi/doubi/master/brook.sh && chmod +x brook.sh && bash brook.sh
}

init(){
    VERSION_CURR=$(uname -r | awk -F '-' '{print $1}')
    VERSION_MIN=4.9.0
    echo -e "\n菜单选项\n"
    PS3="请选择操作: "
    while true; do
      select opt in "安装 TCP BBR 拥塞控制算法" "安装 Docker 服务程序" "创建 SSL 证书" \
        "安装 Gost HTTP/2 代理服务" "安装 ShadowSocks 代理服务" "安装 VPN/L2TP 服务" \
        "安装 Brook 代理服务" "创建证书更新 CronJob" "退出"; do
        case "$REPLY" in
            1) install_bbr;; 2) install_docker;; 3) create_cert;; 4) install_gost;;
            5) install_shadowsocks;; 6) install_vpn;; 7) install_brook;; 8) create_cron_job;;
            9) exit 0;; *) echo -e "${COLOR_ERROR}请输入有效的选项编号。${COLOR_NONE}";;
        esac
        break
      done
    done
}

require_root
init
