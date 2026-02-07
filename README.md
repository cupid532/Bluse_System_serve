## 管理方案
dockge（docker 项目管理）
caddy（一键反代）
- - - 
```
#!/bin/bash

# =================================================================
# 🚀 服务器运维集成管理系统 (标准化 V5.5)
# =================================================================

# 🎨 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# 🔧 首次运行自动安装快捷命令
SCRIPT_PATH="$(readlink -f "$0")"
if [ ! -f ~/.nb_installed ] && [ "$1" != "--skip-install" ]; then
    clear
    echo -e "${CYAN}╔════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║   🔧 检测到首次运行，正在配置快捷命令...      ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════╝${NC}"
    echo ""
    
    # 保存脚本到固定位置
    echo -e "${YELLOW}📦 复制脚本到系统目录...${NC}"
    mkdir -p /opt/scripts
    cp "$SCRIPT_PATH" /opt/scripts/nb.sh
    chmod +x /opt/scripts/nb.sh
    
    # 添加别名到 .bashrc
    echo -e "${YELLOW}⚙️  配置快捷命令...${NC}"
    if ! grep -q "alias nb=" ~/.bashrc 2>/dev/null; then
        echo "" >> ~/.bashrc
        echo "# =============================================" >> ~/.bashrc
        echo "# 运维管理系统快捷命令 (自动生成)" >> ~/.bashrc
        echo "# =============================================" >> ~/.bashrc
        echo "alias nb='bash /opt/scripts/nb.sh'" >> ~/.bashrc
    fi
    
    # 标记已安装
    touch ~/.nb_installed
    
    echo ""
    echo -e "${GREEN}✅ 快捷命令安装完成！${NC}"
    echo -e "${CYAN}┌────────────────────────────────────────────┐${NC}"
    echo -e "${CYAN}│  使用方法：                                │${NC}"
    echo -e "${CYAN}│  1️⃣  执行以下命令使快捷方式生效：          │${NC}"
    echo -e "${CYAN}│     ${YELLOW}source ~/.bashrc${CYAN}                        │${NC}"
    echo -e "${CYAN}│                                            │${NC}"
    echo -e "${CYAN}│  2️⃣  之后直接输入 ${YELLOW}nb${CYAN} 即可启动脚本        │${NC}"
    echo -e "${CYAN}└────────────────────────────────────────────┘${NC}"
    echo ""
    echo -e "${BLUE}💡 提示：脚本已保存到 /opt/scripts/nb.sh${NC}"
    echo ""
    read -p "按回车键继续进入主菜单..." dummy
fi

# --- 1. 状态感知核心函数 ---

# 检查 Docker 服务状态 🐳
get_docker_service_status() {
    if ! command -v docker &> /dev/null; then
        echo -e "${RED}[ 未安装 ]${NC}"
    elif systemctl is-active --quiet docker; then
        echo -e "${GREEN}[ 运行中 ]${NC}"
    else
        echo -e "${RED}[ 已停止 ]${NC}"
    fi
}

# 检查指定容器状态 📦
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
    cat > /data/stacks/caddy/Caddyfile <<'EOF'
{
    email admin@example.com
}
:80 {
    respond /health "OK" 200
}
EOF
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
    echo -e "${GREEN}✅ Dockge 部署成功，访问地址: http://your-server-ip:5001${NC}"
}

# --- 3. 管理子菜单 ---

# Docker 子菜单 🐳
manage_docker_menu() {
    while true; do
        clear
        echo -e "${CYAN}┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓${NC}"
        echo -e "${CYAN}┃        🐳 Docker 基础环境管理          ┃${NC}"
        echo -e "${CYAN}┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${NC}"
        echo -e "当前状态: $(get_docker_service_status)"
        echo -e "------------------------------------------"
        echo -e " 1. 安装 Docker"
        echo -e " 2. 启动服务"
        echo -e " 3. 停止服务"
        echo -e " 4. 彻底卸载并清理残留"
        echo -e " 0. 返回主菜单"
        echo -e "------------------------------------------"
        read -p "选择操作 [0-4]: " d_choice
        case $d_choice in
            1) install_docker ;;
            2) systemctl start docker && echo -e "${GREEN}✅ 服务已启动${NC}" ;;
            3) systemctl stop docker && echo -e "${YELLOW}⚠️  服务已停止${NC}" ;;
            4) 
                read -p "⚠️  确定卸载 Docker？所有容器和数据将被删除 (y/n): " confirm
                if [[ "$confirm" == "y" ]]; then
                    docker stop $(docker ps -aq) 2>/dev/null
                    apt-get purge -y docker-ce docker-ce-cli containerd.io 2>/dev/null
                    rm -rf /var/lib/docker
                    echo -e "${GREEN}✅ 卸载完成${NC}"
                fi
                ;;
            0) break ;;
        esac
        read -p "按回车键继续..." dummy
    done
}

# Caddy 子菜单 🌐
manage_caddy_menu() {
    while true; do
        clear
        echo -e "${PURPLE}┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓${NC}"
        echo -e "${PURPLE}┃        🌐 Caddy 智能网关控制           ┃${NC}"
        echo -e "${PURPLE}┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${NC}"
        echo -e "当前状态: $(get_container_status caddy)"
        echo -e "------------------------------------------"
        echo -e " 1. 部署 / 重置 Caddy"
        echo -e " 2. 启动容器"
        echo -e " 3. 停止容器"
        echo -e " 4. 暂停 (Pause) / 取消暂停"
        echo -e " 5. 编辑配置 (Nano)"
        echo -e " 6. 重载配置 (Reload)"
        echo -e " 33. 彻底卸载 Caddy"
        echo -e " 0. 返回主菜单"
        echo -e "------------------------------------------"
        read -p "选择操作 [0-33]: " c_choice
        case $c_choice in
            1) deploy_caddy ;;
            2) docker start caddy && echo -e "${GREEN}✅ 容器已启动${NC}" ;;
            3) docker stop caddy && echo -e "${YELLOW}⚠️  容器已停止${NC}" ;;
            4) 
                if [ "$(docker inspect -f '{{.State.Paused}}' caddy 2>/dev/null)" == "true" ]; then
                    docker unpause caddy && echo -e "${GREEN}✅ 已取消暂停${NC}"
                else
                    docker pause caddy 2>/dev/null && echo -e "${YELLOW}⏸  已暂停${NC}" || echo -e "${RED}❌ 容器未运行${NC}"
                fi
                ;;
            5) nano /data/stacks/caddy/Caddyfile ;;
            6) 
                docker exec caddy caddy reload --config /etc/caddy/Caddyfile
                [ $? -eq 0 ] && echo -e "${GREEN}✅ 重载成功${NC}" || echo -e "${RED}❌ 重载失败${NC}"
                ;;
            33) 
                read -p "⚠️  确定卸载 Caddy？(y/n): " confirm
                if [[ "$confirm" == "y" ]]; then
                    ( cd /data/stacks/caddy && docker compose down -v ) 
                    rm -rf /data/stacks/caddy
                    echo -e "${GREEN}✅ 卸载完成${NC}"
                fi
                ;;
            0) break ;;
        esac
        read -p "按回车键继续..." dummy
    done
}

# --- 4. 卸载脚本函数 ---

uninstall_script() {
    clear
    echo -e "${RED}╔════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║   ⚠️  卸载脚本并清理所有配置                  ║${NC}"
    echo -e "${RED}╚════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${YELLOW}此操作将删除脚本文件及相关配置${NC}"
    echo ""
    echo -e "${CYAN}💡 注意：此操作不会删除 Docker、Caddy 等已部署的服务${NC}"
    echo ""
    read -p "确定要卸载脚本吗？(输入 yes 确认): " confirm
    
    if [[ "$confirm" == "yes" ]]; then
        echo ""
        echo -e "${YELLOW}🧹 正在卸载...${NC}"
        
        # 删除系统脚本
        rm -f /opt/scripts/nb.sh
        
        # 删除 .bashrc 中的配置
        sed -i '/# =============================================/d' ~/.bashrc
        sed -i '/# 运维管理系统快捷命令 (自动生成)/d' ~/.bashrc
        sed -i "/alias nb=/d" ~/.bashrc
        
        # 删除安装标记
        rm -f ~/.nb_installed
        
        echo -e "${GREEN}✅ 卸载完成！${NC}"
        echo -e "${YELLOW}请执行: source ~/.bashrc${NC}"
        
        # 删除当前脚本文件
        rm -f "$0"
        
        exit 0
    else
        echo -e "${CYAN}❌ 已取消卸载${NC}"
        read -p "按回车键继续..." dummy
    fi
}

# --- 5. 主菜单循环 ---

while true; do
    clear
    echo -e "${BLUE}======================================================${NC}"
    echo -e "          🚀 服务器运维集成管理系统 (V5.5)"
    echo -e "${BLUE}======================================================${NC}"
    printf "  %-25s %-20s\n" "项目名称" "实时运行状态"
    echo -e "  ----------------------------------------------------"
    printf "  %-20s %-20b\n" "1. Docker 基础环境" "$(get_docker_service_status)"
    printf "  %-20s %-20b\n" "2. Dockge 管理面板" "$(get_container_status dockge)"
    printf "  %-20s %-20b\n" "3. Caddy 反代网关"  "$(get_container_status caddy)"
    echo -e "  ----------------------------------------------------"
    echo -e "  00. 🗑️  卸载脚本并清理配置"
    echo -e "  0. 退出脚本"
    echo ""
    read -p "请输入指令 [0-3,00]: " main_choice

    case $main_choice in
        00) uninstall_script ;;
        1) manage_docker_menu ;;
        2) 
            if [ "$(docker ps -a -q -f name=dockge)" ]; then
                echo -e "${YELLOW}Dockge 已部署${NC}"
                read -p "按回车键继续..." dummy
            else
                deploy_dockge
                read -p "按回车键继续..." dummy
            fi
            ;;
        3) manage_caddy_menu ;;
        0) break ;;
        *) 
            echo -e "${RED}❌ 无效选项${NC}"
            read -p "按回车键继续..." dummy
            ;;
    esac
done

cd /root
echo -e "${GREEN}✅ 已安全退出并回到 /root 目录。${NC}"
---
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
