#!/bin/bash

# 自动安装脚本

echo "开始安装 xykt..."

# 检查是否以 root 权限运行
if [ "$(id -u)" != "0" ]; then
    echo "需要管理员权限，正在请求密码..."
    # 使用 sudo 重新运行脚本
    exec sudo "$0" "$@"
fi

# 检查可执行文件是否存在
if [ ! -f "./xykt" ]; then
    echo "错误：未找到 xykt 可执行文件，请先编译项目"
    exit 1
fi

# 复制可执行文件到 /usr/local/bin
cp ./xykt /usr/local/bin/

# 设置执行权限
chmod +x /usr/local/bin/xykt

# 验证安装
echo "安装完成！"
echo "运行 'xykt --help' 查看使用方法"