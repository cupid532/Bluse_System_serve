相信有很多人和我一样刚接触服务器不久，对各种 Linux 操作命令不太熟悉。大部分情况下很多一键脚本的存储地址都是在/opt 内。很显然/opt 是一个系统文件夹，对于系统盘不太大并且有数据盘的服务器不太友好，我就各种折腾，通过各大 AI 的指导组建了以下方法，有更好的方案欢迎留言
- - - 
## 管理方案
dockge（docker 项目管理）
caddy（一键反代）
- - - 
## 1.系统初始化
### 1.1 更新/安装软件包
```bash
apt update
apt install curl -y
```
### 1.2安装 Docker
```bash
echo "📦 正在安装 Docker..."
if ! command -v docker &> /dev/null; then
    curl -fsSL https://get.docker.com | sh
    systemctl enable docker
    systemctl start docker
else
    echo "✓ Docker 已安装"
fi

# 创建专用网络
echo "🌐 创建 Docker 网络..."
docker network create proxynet 2>/dev/null || echo "✓ 网络 proxynet 已存在"

# 创建目录结构
echo "📁 创建目录结构..."
mkdir -p /data/{stacks,shared/{media,downloads,backups},scripts,logs}

# 设置权限（更安全的权限模型）
echo "🔐 配置权限..."
chown -R 1000:1000 /data
chmod 750 /data
chmod -R u+rwX,g+rX,o-rwx /data

# 创建配置文件
echo "📝 创建环境配置..."
cat > /data/.env << 'ENVEOF'
# 全局环境变量
PUID=1000
PGID=1000
TZ=Asia/Shanghai
ENVEOF

# 显示目录结构
echo ""
echo "✅ 环境初始化完毕！目录结构："
tree -L 2 /data 2>/dev/null || ls -lah /data

echo ""
echo "📊 系统信息："
echo "- Docker 版本: $(docker --version)"
echo "- 数据目录: /data"
echo "- 可用空间: $(df -h /data | tail -1 | awk '{print $4}')"
```
---

## 🚀 2. 核心服务部署

### 2.1 部署 Dockge（管理面板）

**访问地址**：`http://<服务器IP>:5001`

```bash
# 复制整段执行：部署 Dockge
mkdir -p /data/stacks/dockge && cd /data/stacks/dockge

cat > compose.yaml << 'EOF'
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
      - /data/stacks:/data/stacks
    environment:
      - DOCKGE_STACKS_DIR=/data/stacks
      - TZ=Asia/Shanghai
    networks:
      - proxynet
    labels:
      - "com.centurylinklabs.watchtower.enable=true"

networks:
  proxynet:
    external: true
EOF

docker compose up -d

echo ""
echo "✅ Dockge 已启动"
echo "📍 访问地址: http://$(hostname -I | awk '{print $1}'):5001"
echo "🔑 首次访问需要设置管理员账号"
```

### 2.2 部署 Caddy（反向代理网关）

```bash
# 复制整段执行：部署 Caddy
mkdir -p /data/stacks/caddy && cd /data/stacks/caddy

# 创建初始 Caddyfile
cat > Caddyfile << 'EOF'
# Caddy 全局配置
{
    email admin@example.com
    admin off
}

# 示例：Dockge 反向代理（需要配置域名 DNS）
# dockge.example.com {
#     reverse_proxy dockge:5001
# }

# 健康检查端点
:80 {
    respond /health 200
}
EOF

cat > compose.yaml << 'EOF'
services:
  caddy:
    image: caddy:2-alpine
    container_name: caddy
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
      - "443:443/udp"  # HTTP/3 支持
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile
      - ./data:/data
      - ./config:/config
      - /data/logs/caddy:/var/log/caddy
    environment:
      - TZ=Asia/Shanghai
    networks:
      - proxynet
    labels:
      - "com.centurylinklabs.watchtower.enable=true"

networks:
  proxynet:
    external: true
EOF

docker compose up -d

echo ""
echo "✅ Caddy 网关已就绪"
echo "📝 配置文件: /data/stacks/caddy/Caddyfile"
echo "🔍 测试命令: curl http://localhost/health"
```

### 2.2.1 Caddy的一键脚本
```bash
# 一键部署 Caddy 管理快捷命令
cat > /usr/local/bin/caddy << 'EOF'
#!/bin/bash

# Caddy 管理脚本
# 工作目录
CADDY_DIR="/data/stacks/caddy"
CADDYFILE="$CADDY_DIR/Caddyfile"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 检查是否在正确的目录
check_dir() {
    if [ ! -d "$CADDY_DIR" ]; then
        echo -e "${RED}错误: Caddy 目录不存在 ($CADDY_DIR)${NC}"
        exit 1
    fi
}

# 显示菜单
show_menu() {
    clear
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}       Caddy 管理工具${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
    echo -e "${GREEN}1.${NC} 启动 Caddy"
    echo -e "${GREEN}2.${NC} 关闭 Caddy"
    echo -e "${GREEN}3.${NC} 编辑配置文件"
    echo -e "${GREEN}4.${NC} 重载配置"
    echo -e "${GREEN}5.${NC} 重启 Caddy"
    echo -e "${GREEN}6.${NC} 查看状态"
    echo -e "${GREEN}7.${NC} 查看日志"
    echo -e "${GREEN}8.${NC} 测试配置"
    echo -e "${GREEN}0.${NC} 退出"
    echo ""
    echo -e "${BLUE}========================================${NC}"
}

# 启动 Caddy
start_caddy() {
    echo -e "${YELLOW}正在启动 Caddy...${NC}"
    cd $CADDY_DIR
    docker compose up -d
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ Caddy 启动成功${NC}"
    else
        echo -e "${RED}❌ Caddy 启动失败${NC}"
    fi
}

# 关闭 Caddy
stop_caddy() {
    echo -e "${YELLOW}正在关闭 Caddy...${NC}"
    cd $CADDY_DIR
    docker compose down
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ Caddy 已关闭${NC}"
    else
        echo -e "${RED}❌ Caddy 关闭失败${NC}"
    fi
}

# 编辑配置文件
edit_config() {
    echo -e "${YELLOW}打开配置文件编辑器...${NC}"
    echo -e "${BLUE}配置文件路径: $CADDYFILE${NC}"
    echo ""
    echo -e "${YELLOW}提示：${NC}"
    
    # 优先使用 nano (最简单)，其次 vim, vi
    if command -v nano &> /dev/null; then
        echo -e "${GREEN}使用 nano 编辑器 (Ctrl+O 保存, Ctrl+X 退出)${NC}"
        sleep 1
        nano $CADDYFILE
    elif command -v vim &> /dev/null; then
        echo -e "${GREEN}使用 vim 编辑器${NC}"
        echo -e "${BLUE}基本操作: 按 i 进入编辑模式, 编辑完成后按 ESC, 然后输入 :wq 保存退出${NC}"
        sleep 2
        vim $CADDYFILE
    elif command -v vi &> /dev/null; then
        echo -e "${GREEN}使用 vi 编辑器${NC}"
        echo -e "${BLUE}基本操作: 按 i 进入编辑模式, 编辑完成后按 ESC, 然后输入 :wq 保存退出${NC}"
        sleep 2
        vi $CADDYFILE
    elif [ -n "$EDITOR" ]; then
        $EDITOR $CADDYFILE
    else
        echo -e "${RED}❌ 未找到可用的编辑器${NC}"
        echo -e "${YELLOW}请先安装编辑器: apt install nano 或 yum install nano${NC}"
        return 1
    fi
    
    # 编辑完成后询问是否重载
    echo ""
    echo -e "${YELLOW}配置文件已编辑完成${NC}"
    read -p "是否重载 Caddy 配置？(y/n): " choice
    case "$choice" in 
        y|Y|yes|YES ) reload_caddy;;
        * ) echo -e "${BLUE}已取消重载${NC}";;
    esac
}

# 重载配置
reload_caddy() {
    echo -e "${YELLOW}正在重载 Caddy 配置...${NC}"
    docker exec caddy caddy reload --config /etc/caddy/Caddyfile
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ 配置重载成功${NC}"
    else
        echo -e "${RED}❌ 配置重载失败${NC}"
    fi
}

# 重启 Caddy
restart_caddy() {
    echo -e "${YELLOW}正在重启 Caddy...${NC}"
    cd $CADDY_DIR
    docker compose restart
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ Caddy 重启成功${NC}"
    else
        echo -e "${RED}❌ Caddy 重启失败${NC}"
    fi
}

# 查看状态
show_status() {
    echo -e "${BLUE}========== Caddy 状态 ==========${NC}"
    cd $CADDY_DIR
    docker compose ps
    echo ""
    echo -e "${BLUE}========== 容器详情 ==========${NC}"
    docker inspect caddy --format='{{.State.Status}}' 2>/dev/null
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}容器运行状态: $(docker inspect caddy --format='{{.State.Status}}')${NC}"
        echo -e "${GREEN}启动时间: $(docker inspect caddy --format='{{.State.StartedAt}}')${NC}"
    else
        echo -e "${RED}容器未运行${NC}"
    fi
}

# 查看日志
show_logs() {
    echo -e "${YELLOW}显示 Caddy 日志 (Ctrl+C 退出)${NC}"
    cd $CADDY_DIR
    docker compose logs -f --tail=50
}

# 测试配置
test_config() {
    echo -e "${YELLOW}正在测试 Caddy 配置...${NC}"
    docker exec caddy caddy validate --config /etc/caddy/Caddyfile
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ 配置文件语法正确${NC}"
    else
        echo -e "${RED}❌ 配置文件有错误${NC}"
    fi
}

# 主循环
main() {
    check_dir
    
    while true; do
        show_menu
        read -p "请选择操作 [0-8]: " choice
        echo ""
        
        case $choice in
            1) start_caddy ;;
            2) stop_caddy ;;
            3) edit_config ;;
            4) reload_caddy ;;
            5) restart_caddy ;;
            6) show_status ;;
            7) show_logs ;;
            8) test_config ;;
            9) 
                echo -e "${GREEN}退出 Caddy 管理工具${NC}"
                exit 0
                ;;
            *)
                echo -e "${RED}无效的选择，请重新输入${NC}"
                ;;
        esac
        
        echo ""
        read -p "按 Enter 键继续..." dummy
    done
}

# 运行主程序
main
EOF

chmod +x /usr/local/bin/caddy

echo ""
echo "✅ Caddy 管理命令已安装完成！"
echo "📝 现在你可以在任何地方输入 'caddy' 来管理 Caddy 了"
echo ""
```

---

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
