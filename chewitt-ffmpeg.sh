#!/bin/bash
set -eE

# コンテナの初期設定（root権限で実行）
pacman-key --init
cp -a keyrings /usr/share/pacman 2>/dev/null || true
pacman-key --populate archlinuxarm
pacman -Syyu --noconfirm

# 必要なパッケージのインストール
pacman -S --noconfirm --need base-devel pacman-contrib wget git devtools

# ビルド用一般ユーザー「builder」の作成とsudo権限付与
useradd -m -G wheel builder

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

chown -R builder:builder /home/builder

# === ここから一般ユーザー「builder」として実行 ===
sudo -u builder bash  << 'EOF_ffmpeg'
set -eE
set -x

cd /home/builder/
mkdir ~/.gnupg 
echo "keyserver-options auto-key-retrieve" > .gnupg/gpg.conf
git init
git config core.sparseCheckout true
git branch -m master
git remote add origin https://github.com/archlinuxarm/PKGBUILDs/
echo "extra/ffmpeg/*" >> .git/info/sparse-checkout


# 必要なフォルダだけをプル
git pull origin master

cd extra/ffmpeg

echo "------------- packaging/packages/ffmpeg ------------------"
ls -la
echo "---------------------------------------------------"

cp PKGBUILD PKGBUILD.org

sed -i "s|x86_64|'aarch64'|" PKGBUILD
sed -i 's|git+https://git.ffmpeg.org/ffmpeg.git?signed#tag=n${pkgver}|git+https://github.com/chewitt/FFmpeg.git|' PKGBUILD
sed -i 's|--enable-vulkan \\|--enable-vulkan \\\n   --enable-v4l2-m2m \\|' PKGBUILD
sed -i "/^prepare()/a mv FFmpeg ffmpeg" PKGBUILD
# KOKO
# 【最適化1】RK3588のCPU(Cortex-A76+A55)に合わせた CFLAGS / CXXFLAGS の強制注入
SED_FLAGS='  export CFLAGS="-O3 -mcpu=cortex-a76.cortex-a55+crypto+dotprod -pipe -fno-plt"\n  export CXXFLAGS="${CFLAGS}"\n'
sed -i "/^build()/a \\${SED_FLAGS}" PKGBUILD

# -s: 依存解決, -r: ビルド後依存削除, -i: 自動インストール, --noconfirm: 確認全>スキップ
updpkgsums
MAKEFLAGS="-j$(nproc)" makepkg -srif --noconfirm 2>&1| tee ~/arch-ffmpeg.txt

echo "🎉 Orange Pi 5 への最適化Mesaの導入がすべて完了しました！"

EOF_ffmpeg
# === 一般ユーザーでの実行ここまで ===

# 出来上がったパッケージをコンテナのルート「/」に配置
cp /home/builder/extra/ffmpeg/*aarch64.pkg.tar.* /MY-rockchip
cp /home/builder/arch-ffmpeg.txt /
