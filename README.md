# VPN 服务安装脚本

本项目提供交互式安装脚本，用于在 Ubuntu 或 CentOS 系统上配置 BBR、Docker、TLS 证书以及若干基于 Docker 的代理/VPN 服务。

## 脚本与系统

| 脚本 | 目标系统 |
| --- | --- |
| `install_ubuntu.sh` | Ubuntu 18.04（脚本按此版本编写） |
| `install_centos.sh` | CentOS 7/8/Stream |

请在与脚本对应的系统上运行。CentOS 脚本要求使用 `root` 用户；Ubuntu 脚本通过 `sudo` 执行系统操作。

## 使用方法

下载项目后，进入脚本目录并运行对应脚本：

```bash
git clone https://github.com/longxiangzhu/vpn.git
cd vpn
bash install_ubuntu.sh
```

CentOS 上运行：

```bash
bash install_centos.sh
```

脚本会显示菜单，输入对应编号选择操作。安装 Docker 后，容器相关菜单项才可使用。首次创建证书前，需先将域名解析到此服务器，并确保外部可以访问验证所需端口。

## 菜单功能

两个脚本提供以下功能：

1. 启用 TCP BBR 拥塞控制算法（内核版本低于 4.9 时提示升级内核）。
2. 安装并启动 Docker。
3. 使用 Certbot standalone 模式申请 TLS 证书。
4. 启动 Gost HTTP/2 代理容器，需要域名、用户名、密码和端口，以及该域名对应的证书。
5. 启动 Shadowsocks 容器，需要密码和监听端口。
6. 启动 VPN/L2TP 容器，需要用户名、密码和 PSK。
7. 下载并运行 Brook 安装脚本。
8. 添加证书续期及重启 Gost 的定时任务。
9. 退出。

依次选择 1，2 ，3，4，8，9

安装完成以后，执行以下命令检查一下。
docker ps       # 确认gost运行正常
 crontab -l       # 确认第8步部署的定时任务成功了
 curl -v "https://www.google.com" --proxy "https://your-domain-name:port" --proxy-user 'user:pwd'




## 注意事项

- 这些脚本会安装软件、修改内核网络参数、启动容器并配置定时任务。运行前请检查服务器和防火墙策略。
- 云服务器安全组及主机防火墙需要放行相应服务端口；脚本不会自动配置云平台安全组。
- CentOS 仓库、EPEL 和 Docker CE 的可用性取决于系统版本及软件源配置。Oracle Linux 9 的 Certbot 从 `ol9_developer_EPEL` 仓库安装。
- BBR 是否可用取决于运行内核及其模块支持。CentOS 脚本不会自动升级内核。
- VPN、Gost 和 Shadowsocks 等服务的口令由用户交互输入。请使用强口令，并妥善保管。
- Ubuntu 脚本面向 Ubuntu 18.04，其软件源配置（包括 Docker、Certbot）可能需要根据当前发行版维护情况调整。

## 来源

Ubuntu 脚本基于原作者 [gongzili456](https://github.com/gongzili456) 的脚本，并包含 [haoel](https://github.com/haoel) 的修改；CentOS 脚本为本项目的 CentOS 适配版本。
