#!/bin/bash
set -eE

# コンテナの初期設定（root権限で実行）
pacman-key --init
cp -a keyrings /usr/share/pacman 2>/dev/null || true
pacman-key --populate archlinuxarm
pacman -Syyu --noconfirm

# 必要なパッケージのインストール
pacman -S --noconfirm --need sudo pacman-contrib wget base-devel git

# ビルド用一般ユーザー「builder」の作成とsudo権限付与
useradd -m -G wheel builder
#usermod -G git builder
mkdir -p /etc/sudoers.d
echo "builder ALL=(ALL:ALL) NOPASSWD: ALL" > /etc/sudoers.d/builder
chmod 0440 /etc/sudoers.d/builder


# 💡【ここを追加】/etc/gitconfig の権限エラーを根本解決する
# もしファイルがなければ空で作成し、すべてのユーザーが読み込める権限（644）を与えます
touch /etc/gitconfig
chmod 644 /etc/gitconfig
# /etc自体のパーミッションも、一般ユーザーが読み込める状態（755）か確認・修正
chmod 755 /etc


# 作業ディレクトリを /home/builder 内に作成し、所有権を builder に変更
#mkdir -p /home/builder/kernel-org
chown -R builder:builder /home/builder

# === ここから一般ユーザー「builder」として実行 ===
sudo -u builder bash  << 'EOF'
set -eE
set -x

cd /home/builder/

# Gitの初期化とSparse Checkout設定
git init
git config core.sparseCheckout true
git branch -m main
git remote add origin https://github.com/iuncuim/manjaro-h616.git
echo "ffmpeg-v4l2-request/*" >> .git/info/sparse-checkout

# 必要なフォルダだけをプル
git pull origin main

cd ffmpeg-v4l2-request
echo "------------- ffmpeg-v4l2-request ------------------"
ls -la
echo "---------------------------------------------------"

# チェックサムの再更新
#updpkgsums

# ffmpeg-v4l2-request のビルド（--noconfirm で依存関係の自動インストールを許可）
MAKEFLAGS="-j$(nproc)" makepkg -sri --noconfirm 2>&1|tee ~/arch-build-log.txt

EOF
# === 一般ユーザーでの実行ここまで ===

# 出来上がったパッケージをコンテナのルート「/」に配置
cp /home/builder/ffmpeg-v4l2-request/ffmpeg-[0-9]*-aarch64.pkg.tar.* /

# ビルドログを root 権限で / に退避（base_kernel.sh が回収できるようにする）
cp /home/builder/*.txt / 2>/dev/null || true

