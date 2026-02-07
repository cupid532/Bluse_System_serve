## 管理方案
dockge（docker 项目管理）
caddy（一键反代）
- - - 
```
#!/bin/bash

# =================================================================
# 🚀 服务器运维集成管理系统 (V6.0 - 增强交互版)
# =================================================================

# 🎨 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# --- 0. 基础工具函数 ---

# 🛡️ IP 获取函数
get_public_ip() {
    local version=$1
    local ip=""
    ip=$(curl -s -"$version" --max-time 2 --user-agent "Mozilla/5.0" https://api.ip.sb/ip 2>/dev/null)
    if [[ ! "$ip" =~ ^[0-9a-fA-F:.]+$ ]]; then
        ip=$(curl -s -"$version" --max-time 2 https://icanhazip.com 2>/dev/null)
    fi
    if [[ ! "$ip" =~ ^[0-9a-fA-F:.]+$ ]]; then
        if [ "$version" == "4" ]; then
            ip=$(hostname -I | awk '{print $1}')
        else
            ip=$(ip -6 addr show scope global | grep inet6 | awk '{print $2}' | cut -d/ -f1 | head -n1)
        fi
    fi
    if [ -z "$ip" ] || [[ "$ip" == *"html"* ]]; then echo "未检测到"; else echo "$ip"; fi
}

# 🌐 初始化：获取网络信息
echo -e "${YELLOW}正在探测网络配置...${NC}"
IPV4=$(get_public_ip 4)
IPV6=$(get_public_ip 6)

# 🔧 首次运行自动安装快捷命令
SCRIPT_PATH="$(readlink -f "$0")"
if [ ! -f ~/.nb_installed ] && [ "$1" != "--skip-install" ]; then
    mkdir -p /opt/scripts
    cp "$SCRIPT_PATH" /opt/scripts/nb.sh
    chmod +x /opt/scripts/nb.sh
    if ! grep -q "alias nb=" ~/.bashrc 2>/dev/null; then
        echo "alias nb='bash /opt/scripts/nb.sh'" >> ~/.bashrc
    fi
    touch ~/.nb_installed
fi

# 获取内存
get_memory_usage() {
    free -m | awk 'NR==2{printf "%s/%sMB (%.0f%%)", $3,$2,$3*100/$2 }'
}

# --- 💡 新增：动态显示访问地址函数 ---
# 参数1: 端口号
show_access_info() {
    local port=$1
    echo -e "${BLUE}--------------------------------------------------------------${NC}"
    echo -e " 🔗 访问入口:"
    if [ "$IPV4" != "未检测到" ]; then
        echo -e "    IPv4: ${CYAN}http://${IPV4}:${port}${NC}"
    fi
    if [ "$IPV6" != "未检测到" ]; then
        echo -e "    IPv6: ${CYAN}http://[${IPV6}]:${port}${NC}"
    fi
}

# 统一页头显示
show_header() {
    local title="$1"
    clear
    echo -e "${BLUE}==============================================================${NC}"
    echo -e " 🚀 运维集成系统 ${YELLOW}[V6.0]${NC} | ${CYAN}$title${NC}"
    echo -e "${BLUE}==============================================================${NC}"
    echo -e " 🖥️  IPv4: ${PURPLE}$IPV4${NC}"
    echo -e " 🌐 IPv6: ${PURPLE}$IPV6${NC}"
    echo -e " 💾 内存: $(get_memory_usage)"
    echo -e "${BLUE}--------------------------------------------------------------${NC}"
}

# --- 1. 状态感知核心函数 ---

get_docker_service_status() {
    if ! command -v docker &> /dev/null; then echo -e "${RED}[ 未安装 ]${NC}";
    elif systemctl is-active --quiet docker; then echo -e "${GREEN}[ 运行中 ]${NC}";
    else echo -e "${RED}[ 已停止 ]${NC}"; fi
}

get_container_status() {
    local status=$(docker inspect -f '{{.State.Status}}' "$1" 2>/dev/null)
    case "$status" in
        running) echo -e "${GREEN}[ 运行中 ]${NC}" ;;
        paused)  echo -e "${YELLOW}[ 已暂停 ]${NC}" ;;
        exited)  echo -e "${RED}[ 已停止 ]${NC}" ;;
        *)       echo -e "${RED}[ 未部署 ]${NC}" ;;
    esac
}

# --- 2. 部署函数 ---

install_docker() {
    echo -e "${YELLOW}正在安装 Docker 环境...${NC}"
    curl -fsSL https://get.docker.com | sh
    systemctl enable --now docker
    docker network create proxynet 2>/dev/null || true
    echo -e "${GREEN}✅ 安装完成${NC}"
}

deploy_caddy() {
    echo -e "${YELLOW}正在部署 Caddy...${NC}"
    mkdir -p /data/stacks/caddy /data/logs/caddy
    if [ ! -f /data/stacks/caddy/Caddyfile ]; then
        echo "{ email admin@example.com }" > /data/stacks/caddy/Caddyfile
        echo ":80 { respond /health \"OK\" 200 }" >> /data/stacks/caddy/Caddyfile
    fi
    cat > /data/stacks/caddy/compose.yaml <<'EOF'
services:
  caddy:
    image: caddy:2-alpine
    container_name: caddy
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
      - "443:443/udp"
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile
      - ./data:/data
      - ./config:/config
      - /data/logs/caddy:/var/log/caddy
    networks:
      - proxynet
networks:
  proxynet:
    external: true
EOF
    ( cd /data/stacks/caddy && docker compose up -d )
    echo -e "${GREEN}✅ Caddy 部署成功${NC}"
}

deploy_dockge() {
    echo -e "${YELLOW}正在部署 Dockge...${NC}"
    mkdir -p /data/stacks/dockge /data/stacks
    cat > /data/stacks/dockge/compose.yaml <<'EOF'
services:
  dockge:
    image: louislam/dockge:1
    container_name: dockge
    restart: unless-stopped
    ports:
      - "5001:5001"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - ./data:/app/data
      - /data/stacks:/opt/stacks
    environment:
      - DOCKGE_STACKS_DIR=/opt/stacks
EOF
    ( cd /data/stacks/dockge && docker compose up -d )
    echo -e "${GREEN}✅ Dockge 部署成功${NC}"
}

add_caddy_proxy() {
    local caddyfile="/data/stacks/caddy/Caddyfile"
    if [ ! -f "$caddyfile" ]; then echo -e "${RED}❌ Caddy 未部署${NC}"; return; fi

    echo -e "${CYAN}--- 新增反向代理 (简易模式) ---${NC}"
    read -p "1️⃣  请输入域名 (例如: blog.test.com): " domain
    [ -z "$domain" ] && return
    read -p "2️⃣  请输入目标 IP:端口 (例如: 127.0.0.1:8080): " target
    [ -z "$target" ] && return

    echo ""
    echo -e "添加: ${GREEN}$domain${NC} ➡️  ${GREEN}$target${NC}"
    read -p "确认? (y/n): " confirm
    if [[ "$confirm" == "y" ]]; then
        echo -e "\n# --- Proxy: $domain ---\n$domain {\n    reverse_proxy $target\n}" >> "$caddyfile"
        docker exec caddy caddy reload --config /etc/caddy/Caddyfile
        echo -e "${GREEN}✅ 配置已生效${NC}"
    fi
}

# --- 3. 管理子菜单 ---

manage_docker_menu() {
    while true; do
        show_header "Docker 管理"
        echo -e " Docker状态: $(get_docker_service_status)"
        if command -v docker &> /dev/null; then
            echo -e " 版本信息: $(docker --version | cut -d ',' -f1)"
        fi
        echo -e "--------------------------------------------------------------"
        echo -e " 1. 安装 Docker"
        echo -e " 2. 启动服务"
        echo -e " 3. 停止服务"
        echo -e " 4. 查看所有容器 (ps -a)"
        echo -e " 5. 彻底卸载 Docker"
        echo -e " 0. 返回主菜单"
        echo -e "--------------------------------------------------------------"
        read -p "选择操作 [0-5]: " choice
        case $choice in
            1) install_docker ;;
            2) systemctl start docker && echo -e "${GREEN}✅ 已启动${NC}" ;;
            3) systemctl stop docker && echo -e "${YELLOW}⚠️  已停止${NC}" ;;
            4) docker ps -a ;;
            5) 
                read -p "⚠️  确认卸载? (y/n): " cf
                [[ "$cf" == "y" ]] && apt-get purge -y docker-ce docker-ce-cli containerd.io && rm -rf /var/lib/docker && echo -e "${GREEN}✅ 已卸载${NC}" 
                ;;
            0) break ;;
        esac
        read -p "按回车键继续..."
    done
}

# --- 🔥 新增：Dockge 独立管理菜单 ---
manage_dockge_menu() {
    while true; do
        show_header "Dockge 面板管理"
        echo -e " 容器状态: $(get_container_status dockge)"
        
        # 🚀 只有当容器存在时，才显示访问链接
        if [ "$(docker ps -q -f name=dockge)" ]; then
            show_access_info "5001"
        fi

        echo -e "--------------------------------------------------------------"
        echo -e " 1. 部署/更新 Dockge"
        echo -e " 2. 启动容器"
        echo -e " 3. 暂停容器"
        echo -e " 4. 重启容器"
        echo -e " 5. 查看实时日志 (Ctrl+C 退出)"
        echo -e " 33. 卸载 Dockge"
        echo -e " 0. 返回主菜单"
        echo -e "--------------------------------------------------------------"
        read -p "选择操作 [0-33]: " choice
        case $choice in
            1) deploy_dockge ;;
            2) docker start dockge && echo -e "${GREEN}✅ 已启动${NC}" ;;
            3) docker stop dockge && echo -e "${YELLOW}⚠️  已停止${NC}" ;;
            4) docker restart dockge && echo -e "${GREEN}✅ 已重启${NC}" ;;
            5) docker logs -f --tail 100 dockge ;;
            33) 
                read -p "确认删除 Dockge 容器? (数据保留) (y/n): " c
                if [[ "$c" == "y" ]]; then
                    (cd /data/stacks/dockge && docker compose down)
                    echo -e "${GREEN}✅ 容器已删除 (数据位于 /data/stacks/dockge)${NC}" 
                fi
                ;;
            0) break ;;
        esac
        read -p "按回车键继续..."
    done
}

manage_caddy_menu() {
    while true; do
        show_header "Caddy 网关管理"
        echo -e " 容器状态: $(get_container_status caddy)"
        
        if [ "$(docker ps -q -f name=caddy)" ]; then
            show_access_info "80"
        fi

        echo -e "--------------------------------------------------------------"
        echo -e " 1. 部署/重置 Caddy"
        echo -e " 2. 启动容器"
        echo -e " 3. 停止容器"
        echo -e " 4. 重载配置 (Reload)"
        echo -e " 5. 查看实时日志"
        echo -e "${CYAN} 6. 新增反向代理 (向导)${NC}"
        echo -e " 7. 编辑配置文件 (Nano)"
        echo -e " 33. 卸载 Caddy"
        echo -e " 0. 返回主菜单"
        echo -e "--------------------------------------------------------------"
        read -p "选择操作 [0-33]: " choice
        case $choice in
            1) deploy_caddy ;;
            2) docker start caddy && echo -e "${GREEN}✅ 已启动${NC}" ;;
            3) docker stop caddy && echo -e "${YELLOW}⚠️  已停止${NC}" ;;
            4) docker exec caddy caddy reload --config /etc/caddy/Caddyfile && echo -e "${GREEN}✅ 重载成功${NC}" ;;
            5) docker logs -f --tail 50 caddy ;;
            6) add_caddy_proxy ;;
            7) nano /data/stacks/caddy/Caddyfile ;;
            33) [[ "$(read -p "确认卸载? (y/n): " c; echo $c)" == "y" ]] && (cd /data/stacks/caddy && docker compose down -v) && rm -rf /data/stacks/caddy && echo -e "${GREEN}✅ 已卸载${NC}" ;;
            0) break ;;
        esac
        read -p "按回车键继续..."
    done
}

uninstall_script() {
    read -p "确定要卸载脚本吗？(y/n): " confirm
    if [[ "$confirm" == "y" ]]; then
        rm -f /opt/scripts/nb.sh
        sed -i '/alias nb=/d' ~/.bashrc
        rm -f ~/.nb_installed
        echo -e "${GREEN}✅ 脚本已卸载${NC}"
        rm -f "$0"
        exit 0
    fi
}

# --- 4. 主菜单循环 ---

while true; do
    show_header "主菜单"
    printf " %-20s %-20b\n" "1. Docker 环境" "$(get_docker_service_status)"
    printf " %-20s %-20b\n" "2. Dockge 面板" "$(get_container_status dockge)"
    printf " %-20s %-20b\n" "3. Caddy 网关"  "$(get_container_status caddy)"
    echo -e "--------------------------------------------------------------"
    echo -e " 00. 卸载脚本"
    echo -e " 0. 退出"
    echo ""
    read -p "请输入指令: " main_choice

    case $main_choice in
        00) uninstall_script ;;
        1) manage_docker_menu ;;
        2) manage_dockge_menu ;; 
        3) manage_caddy_menu ;;
        0) break ;;
        *) echo -e "${RED}无效选项${NC}"; read -p "按回车..." ;;
    esac
done

cd /root
echo -e "${GREEN}✅ 已退出。${NC}"
```
## 🤖 3. AI 提示词

### 标准提示词模板
```bash
你是我的系统架构师。请基于 **"Infrastructure as Data"** 架构规范，为我生成符合生产环境标准的 Docker Compose 部署方案。

【角色目标】
生成一份“零摩擦”的部署配置，确保服务启动即通过，无需手动进入容器修改配置，且文件结构清晰、权限正确。

【强制规范】

1. **输出顺序标准（严格执行）**
    * **第一步 (`init.sh`)**：文件系统初始化、权限修正、核心配置预埋。
    * **第二步 (`compose.yaml`)**：容器编排定义。
    * **第三步 (`Caddyfile`)**：反向代理配置。

2. **持久化目录标准**
    * 应用配置：挂载 `./data`（当前 compose 所在目录下的子目录）。
    * 媒体/大文件：挂载 `/data/shared/media`（全局共享，只读建议）。
    * 数据库文件：挂载 `./data/db`。
    * **权限原则**：必须确保宿主机挂载目录的权限归属为 `PUID:PGID`。

3. **网络与端口策略**
    * **显式映射端口**：必须使用 `ports` 暴露主要端口（格式 `宿主机端口:容器端口`），以便支持直连调试。
    * **外部网络**：必须加入外部网络 `proxynet`（用于 Caddy 内部通信）。
    * **敏感服务检查**：如果服务属于易受攻击或有默认访问限制的类型（如 qBittorrent, Jupyter, Redis）：
        * 必须在 `init.sh` 中预生成配置文件以允许非 Localhost 访问（关闭 HostHeaderValidation 等）。
        * 或者在注释中明确提示是否需要为了安全而移除 `ports` 映射。

4. **环境与容器配置**
    * **环境变量**：`PUID=1000`, `PGID=1000`, `TZ=Asia/Shanghai`。
    * **重启策略**：`restart: unless-stopped`。
    * **更新管理**：添加 label `com.centurylinklabs.watchtower.enable=true`。
    * **安全性**：禁止使用默认密码（使用 `environment` 传递强密码或随机生成），非必要不使用 root 运行。

【输出要求】

**请不要输出任何解释性废话，直接按顺序输出以下三个代码块：**

#### Block 1: `init.sh`
* **功能**：一键初始化脚本。
* **内容要求**：
    1.  `mkdir -p` 创建所有挂载目录。
    2.  **[关键] 配置预埋**：对于 qBittorrent 等默认拒绝公网 IP 访问的服务，**必须**在此处使用 `cat > ... <<EOF` 预写入配置文件（如关闭 CSRF/HostHeader 检查），确保服务启动后不会报 "Unauthorized"。
    3.  `chown -R 1000:1000` 修正目录权限。
    4.  输出 "Initialization complete" 提示。

#### Block 2: `compose.yaml`
* 包含完整的服务定义，显式端口映射，网络配置。

#### Block 3: `Caddyfile`
* 格式：`服务名.example.com { reverse_proxy 容器名:内部端口 }`

---

**【当前任务】**

请为我部署：[在此处输入服务名称]
```
---


## 🎯 快速开始检查清单

- [ ] 数据盘已挂载到 `/data`
- [ ] 执行初始化脚本
- [ ] 部署 Dockge 管理面板
- [ ] 部署 Caddy 反向代理
- [ ] 配置自动备份
- [ ] 测试服务部署
- [ ] 配置域名解析（可选）
- [ ] 启用 HTTPS（可选）

**恭喜！您的服务器架构已就绪。** 🎉
