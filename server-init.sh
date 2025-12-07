#!/bin/bash
# ============================================
# 服务器初始化脚本 - 修复版
# 使用方法: sudo bash server-init.sh [mount|init|all]
# ============================================

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${GREEN}✓${NC} $1"; }
log_warn() { echo -e "${YELLOW}⚠${NC} $1"; }
log_error() { echo -e "${RED}✗${NC} $1"; }
log_step() { echo -e "${BLUE}➜${NC} $1"; }

# ============================================
# 脚本 1: 挂载数据盘
# ============================================
mount_data_disk() {
    echo "========================================="
    echo "  数据盘挂载工具"
    echo "========================================="
    echo ""
    
    # 检查 root 权限
    if [ "$EUID" -ne 0 ]; then 
        log_error "请使用 root 权限执行"
        return 1
    fi
    
    # 检查 /data 是否已挂载
    if mountpoint -q /data 2>/dev/null; then
        log_info "/data 已挂载"
        df -h /data
        return 0
    fi
    
    # 显示未挂载的磁盘
    echo "💾 扫描未挂载的磁盘..."
    echo ""
    lsblk -o NAME,SIZE,TYPE,MOUNTPOINT | grep disk | grep -v "/$" || true
    echo ""
    
    # 手动输入磁盘
    read -p "请输入要挂载的磁盘名（例如 sdb 或 vdb，输入 0 跳过）: " DISK_NAME
    
    if [ "$DISK_NAME" = "0" ]; then
        log_warn "跳过磁盘挂载，使用根目录创建 /data"
        mkdir -p /data
        return 0
    fi
    
    DISK="/dev/$DISK_NAME"
    
    # 验证磁盘存在
    if [ ! -b "$DISK" ]; then
        log_error "磁盘 $DISK 不存在"
        return 1
    fi
    
    # 显示磁盘信息
    DISK_SIZE=$(lsblk -ndo SIZE "$DISK" 2>/dev/null || echo "未知")
    echo ""
    log_warn "即将格式化磁盘:"
    echo "   设备: $DISK"
    echo "   大小: $DISK_SIZE"
    echo "   挂载点: /data"
    echo ""
    log_warn "警告: 此操作将清空磁盘所有数据！"
    echo ""
    
    # 二次确认
    read -p "确认格式化并挂载？(输入 YES 继续): " confirm
    
    if [ "$confirm" != "YES" ]; then
        log_warn "操作已取消"
        return 1
    fi
    
    # 开始操作
    echo ""
    log_step "正在格式化 $DISK ..."
    if ! mkfs.ext4 -F -L DATA_DISK "$DISK"; then
        log_error "格式化失败"
        return 1
    fi
    
    log_step "创建挂载点 /data ..."
    mkdir -p /data
    
    log_step "挂载磁盘..."
    if ! mount "$DISK" /data; then
        log_error "挂载失败"
        return 1
    fi
    
    log_step "配置开机自动挂载..."
    UUID=$(blkid -s UUID -o value "$DISK")
    
    # 备份 fstab
    cp /etc/fstab /etc/fstab.backup.$(date +%Y%m%d_%H%M%S)
    
    # 添加到 fstab（检查是否已存在）
    if ! grep -q "$UUID" /etc/fstab 2>/dev/null; then
        echo "UUID=$UUID /data ext4 defaults,nofail 0 2" >> /etc/fstab
        log_info "已添加到 /etc/fstab"
    fi
    
    echo ""
    echo "========================================="
    log_info "数据盘挂载完成！"
    echo "========================================="
    echo ""
    df -h /data
    echo ""
}

# ============================================
# 脚本 2: 初始化环境
# ============================================
init_environment() {
    echo "========================================="
    echo "  Docker 环境初始化"
    echo "========================================="
    echo ""
    
    # 检查 root 权限
    if [ "$EUID" -ne 0 ]; then 
        log_error "请使用 root 权限执行"
        return 1
    fi
    
    # 检查 /data 是否存在
    if [ ! -d /data ]; then
        log_warn "/data 目录不存在，正在创建..."
        mkdir -p /data
    fi
    
    # 1. 安装 Docker
    echo "📦 [1/5] 检查 Docker..."
    if ! command -v docker &> /dev/null; then
        log_step "正在安装 Docker（可能需要几分钟）..."
        if curl -fsSL https://get.docker.com | sh; then
            systemctl enable docker 2>/dev/null
            systemctl start docker 2>/dev/null
            
            # 配置 Docker 镜像加速
            mkdir -p /etc/docker
            cat > /etc/docker/daemon.json <<'DOCKEREOF'
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "2"
  },
  "registry-mirrors": [
    "https://docker.1panel.live",
    "https://docker.m.daocloud.io"
  ]
}
DOCKEREOF
            systemctl restart docker 2>/dev/null
            log_info "Docker 安装完成"
        else
            log_error "Docker 安装失败"
            return 1
        fi
    else
        log_info "Docker 已安装: $(docker --version)"
    fi
    
    # 2. 创建 Docker 网络
    echo ""
    echo "🌐 [2/5] 创建 Docker 网络..."
    if docker network create --subnet=172.30.0.0/16 proxynet 2>/dev/null; then
        log_info "网络 proxynet 已创建"
    else
        log_info "网络 proxynet 已存在"
    fi
    
    # 3. 创建目录结构
    echo ""
    echo "📁 [3/5] 创建目录结构..."
    mkdir -p /data/{stacks,shared/{media,downloads,configs,backups},scripts,logs}
    log_info "目录结构已创建"
    
    # 4. 创建配置文件
    echo ""
    echo "📝 [4/5] 创建配置文件..."
    
    # 环境变量配置
    cat > /data/.env <<'ENVEOF'
# 全局环境变量
PUID=1000
PGID=1000
TZ=Asia/Shanghai

# 路径配置
DATA_ROOT=/data
MEDIA_DIR=/data/shared/media
DOWNLOAD_DIR=/data/shared/downloads
CONFIG_DIR=/data/shared/configs
ENVEOF
    
    # 快速导航脚本
    cat > /data/scripts/goto.sh <<'GOTOEOF'
#!/bin/bash
# 快速跳转脚本
case "$1" in
    stacks|s) cd /data/stacks && pwd ;;
    media|m) cd /data/shared/media && pwd ;;
    downloads|d) cd /data/shared/downloads && pwd ;;
    configs|c) cd /data/shared/configs && pwd ;;
    logs|l) cd /data/logs && pwd ;;
    *) 
        echo "用法: goto [stacks|media|downloads|configs|logs]"
        echo "简写: goto [s|m|d|c|l]"
        ;;
esac
GOTOEOF
    chmod +x /data/scripts/goto.sh
    
    # 清理脚本
    cat > /data/scripts/cleanup.sh <<'CLEANEOF'
#!/bin/bash
# Docker 和日志清理脚本
echo "🧹 清理 Docker 垃圾..."
docker system prune -af --volumes
echo "🧹 清理旧日志 (30天前)..."
find /data/logs -type f -name "*.log" -mtime +30 -delete 2>/dev/null
echo "✅ 清理完成"
CLEANEOF
    chmod +x /data/scripts/cleanup.sh
    
    log_info "配置文件已创建"
    
    # 5. 设置权限
    echo ""
    echo "🔐 [5/5] 配置权限..."
    chown -R 1000:1000 /data 2>/dev/null || true
    chmod 755 /data
    find /data -type d -exec chmod 755 {} \; 2>/dev/null || true
    find /data -type f -exec chmod 644 {} \; 2>/dev/null || true
    chmod +x /data/scripts/*.sh 2>/dev/null || true
    log_info "权限配置完成"
    
    # 添加快捷命令
    if ! grep -q "goto.sh" ~/.bashrc 2>/dev/null; then
        echo "alias goto='source /data/scripts/goto.sh'" >> ~/.bashrc
        log_info "已添加快捷命令 goto (重新登录生效)"
    fi
    
    # 完成总结
    echo ""
    echo "========================================="
    log_info "环境初始化完成！"
    echo "========================================="
    echo ""
    echo "📊 系统信息:"
    echo "  - Docker: $(docker --version 2>/dev/null || echo '未安装')"
    echo "  - 数据目录: /data"
    echo "  - 可用空间: $(df -h /data 2>/dev/null | tail -1 | awk '{print $4}' || echo '未知')"
    echo ""
    echo "📁 目录结构:"
    if command -v tree &>/dev/null; then
        tree -L 2 /data 2>/dev/null || ls -lah /data
    else
        ls -lah /data
    fi
    echo ""
    echo "🚀 快速开始:"
    echo "  1. 进入工作目录: cd /data/stacks"
    echo "  2. 查看环境变量: cat /data/.env"
    echo "  3. 快速跳转: goto stacks  (或 goto s)"
    echo "  4. 清理垃圾: bash /data/scripts/cleanup.sh"
    echo ""
}

# ============================================
# 主菜单
# ============================================
show_main_menu() {
    clear
    echo ""
    echo "========================================="
    echo "  服务器初始化工具"
    echo "========================================="
    echo ""
    echo "请选择要执行的操作:"
    echo ""
    echo "  1) 挂载数据盘到 /data"
    echo "  2) 初始化 Docker 环境"
    echo "  3) 完整安装 (挂载 + 环境)"
    echo "  0) 退出"
    echo ""
    echo "========================================="
    echo ""
}

# ============================================
# 主程序
# ============================================
main() {
    # 命令行参数模式
    if [ "$#" -eq 1 ]; then
        case "$1" in
            mount) 
                mount_data_disk
                exit $?
                ;;
            init) 
                init_environment
                exit $?
                ;;
            all) 
                mount_data_disk
                if [ $? -eq 0 ]; then
                    echo ""
                    read -p "按回车继续初始化环境..." -t 10 || true
                    init_environment
                fi
                exit $?
                ;;
            *) 
                echo "用法: $0 [mount|init|all]"
                exit 1
                ;;
        esac
    fi
    
    # 交互式菜单模式
    while true; do
        show_main_menu
        read -p "请选择 [0-3]: " choice
        echo ""
        
        case "$choice" in
            1) 
                mount_data_disk
                echo ""
                read -p "按回车返回菜单..." -t 5 || true
                ;;
            2) 
                init_environment
                echo ""
                read -p "按回车返回菜单..." -t 5 || true
                ;;
            3) 
                mount_data_disk
                if [ $? -eq 0 ]; then
                    echo ""
                    read -p "按回车继续初始化环境..." -t 10 || true
                    init_environment
                fi
                echo ""
                read -p "按回车返回菜单..." -t 5 || true
                ;;
            0) 
                echo "👋 退出脚本"
                exit 0
                ;;
            *) 
                log_error "无效选择，请输入 0-3"
                sleep 2
                ;;
        esac
    done
}

# 执行主程序
main "$@"
