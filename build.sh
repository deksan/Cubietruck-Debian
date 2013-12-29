#!/bin/bash

DEST=/tmp/Cubie


echo "Building Cubietruck-Debian in $DEST"
sleep 3

#Requires root ..
#--------------------------------------------------------------------------------
# Downloading necessary files
#--------------------------------------------------------------------------------

sudo apt-get -q -y install binfmt-support bison build-essential ccache debootstrap flex gawk gcc-arm-linux-gnueabi gcc-arm-linux-gnueabihf gettext git linux-headers-generic linux-image-generic lvm2 qemu-user-static texinfo texlive u-boot-tools uuid-dev zlib1g-dev unzip libncurses5-dev

#--------------------------------------------------------------------------------
# Preparing output / destination files
#--------------------------------------------------------------------------------

mkdir -p $DEST/output
cp output/uEnv.txt $DEST/output

git clone https://github.com/cubieboard/u-boot-sunxi $DEST/u-boot-sunxi # Boot loader
git clone https://github.com/linux-sunxi/sunxi-tools.git $DEST/sunxi-tools # Allwinner tools
git clone https://github.com/cubieboard/cubie_configs $DEST/cubie_configs # Hardware configurations
git clone https://github.com/cubieboard/linux-sunxi/ $DEST/linux-sunxi # Kernel 3.4.61+

# Applying Patch for 2gb memory
patch -f $DEST/u-boot-sunxi/include/configs/sunxi-common.h < patch/memory.patch

#Change Video output ( TODO add a param so the user can choose that ?)
sed -e 's/output_type = 3/output_type = 4/g' $DEST/cubie_configs/sysconfig/linux/cubietruck.fex > $DEST/cubie_configs/sysconfig/linux/cubietruck-vga.fex



#--------------------------------------------------------------------------------
# Compiling everything
#--------------------------------------------------------------------------------

cd $DEST/u-boot-sunxi
# boot loader
make -j2 'cubietruck' CROSS_COMPILE=arm-linux-gnueabihf-
cd ..
cd sunxi-tools
# sunxi-tools
make fex2bin
cp fex2bin /usr/bin/
cd ..
# hardware configuration
fex2bin $DEST/cubie_configs/sysconfig/linux/cubietruck-vga.fex $DEST/output/script.bin
fex2bin $DEST/cubie_configs/sysconfig/linux/cubietruck.fex $DEST/output/script-hdmi.bin
cd linux-sunxi
# kernel image
make -j2 ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- sun7i_defconfig
# get proven config
wget https://www.dropbox.com/s/jvccoerm8mka7e8/config -O .config
make -j2 ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- uImage modules
make -j2 ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- INSTALL_MOD_PATH=output modules_install

#--------------------------------------------------------------------------------
# Creating SD Images
#--------------------------------------------------------------------------------
cd $DEST/output
# create 1Gb image and mount image to /dev/loop0
dd if=/dev/zero of=debian_rootfs.raw bs=1M count=1000
losetup /dev/loop0 debian_rootfs.raw 

# make image bootable
dd if=$DEST/u-boot-sunxi/u-boot-sunxi-with-spl.bin of=/dev/loop0 bs=1024 seek=8

# create one partition starting at 2048 which is default
(echo n; echo p; echo 1; echo; echo; echo w) | fdisk /dev/loop0 >> /dev/null
# just to make sure
partprobe

# 2048 (start) x 512 (block size) = where to mount partition
losetup -o 1048576 /dev/loop1  /dev/loop0
# create filesystem
mkfs.ext4 /dev/loop1
# create mount point and mount image 
mkdir -p $DEST/output/sdcard/
mount /dev/loop1 $DEST/output/sdcard/

# install base system
debootstrap --no-check-gpg --arch=armhf --foreign wheezy $DEST/output/sdcard/
# we need this
cp /usr/bin/qemu-arm-static $DEST/output/sdcard/usr/bin/
# second stage
chroot $DEST/output/sdcard /bin/bash -c "/debootstrap/debootstrap --second-stage"

# apt list
cat <<EOT > $DEST/output/sdcard/etc/apt/sources.list
deb http://http.debian.net/debian wheezy main contrib non-free
deb-src http://http.debian.net/debian wheezy main contrib non-free
deb http://http.debian.net/debian wheezy-updates main contrib non-free
deb-src http://http.debian.net/debian wheezy-updates main contrib non-free
deb http://security.debian.org/debian-security wheezy/updates main contrib non-free
deb-src http://security.debian.org/debian-security wheezy/updates main contrib non-free
EOT

# update
chroot $DEST/output/sdcard /bin/bash -c "apt-get update"
chroot $DEST/output/sdcard /bin/bash -c "export LANG=C"    

# set up 'apt
cat <<END > $DEST/output/sdcard/etc/apt/apt.conf.d/71-no-recommends
APT::Install-Recommends "0";
APT::Install-Suggests "0";
END

# scripts for autoresize at first boot from cubian
cd $DEST/output/sdcard/etc/init.d
wget https://www.dropbox.com/s/jytplpmc80nvc3q/cubian-firstrun
wget https://www.dropbox.com/s/pwlsua9xran60ji/cubian-resize2fs

# make it executable
chroot $DEST/output/sdcard /bin/bash -c "chmod +x /etc/init.d/cubian-*"
# and startable on boot
chroot $DEST/output/sdcard /bin/bash -c "update-rc.d cubian-firstrun defaults" 
# install and configure locales
chroot $DEST/output/sdcard /bin/bash -c "apt-get -q -y install locales"
chroot $DEST/output/sdcard /bin/bash -c "dpkg-reconfigure locales"
chroot $DEST/output/sdcard /bin/bash -c "export LANG=en_US.UTF-8"
chroot $DEST/output/sdcard /bin/bash -c "apt-get -q -y install openssh-server module-init-tools dhcp3-client udev ifupdown iproute dropbear iputils-ping ntpdate usbutils uboot-envtools pciutils wireless-tools wpasupplicant procps libnl-dev parted" 
chroot $DEST/output/sdcard /bin/bash -c "apt-get -q -y upgrade"

# set password
chroot $DEST/output/sdcard /bin/bash -c "passwd" 

# set hostname 
echo cubie > $DEST/output/sdcard/etc/hostname

# load modules
cat <<EOT >> $DEST/output/sdcard/etc/modules
gpio_sunxi
bcmdhd
sunxi_gmac
EOT

# create interfaces configuration
cat <<EOT >> $DEST/output/sdcard/etc/network/interfaces
auto eth0 wlan0
allow-hotplug eth0
iface eth0 inet dhcp
        hwaddress ether AE:50:30:27:5A:CF # change this
allow-hotplug wlan0
iface wlan0 inet dhcp
    wpa-ssid SSID 
    wpa-psk xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
# to generate proper encrypted key: wpa_passphrase yourSSID yourpassword
EOT

# enable serial console (Debian/sysvinit way)
echo T0:2345:respawn:/sbin/getty -L ttyS0 115200 vt100 >> $DEST/output/sdcard/etc/inittab

cp $DEST/output/uEnv.txt $DEST/output/sdcard/boot/
cp $DEST/output/script.bin $DEST/output/sdcard/boot/
cp $DEST/linux-sunxi/arch/arm/boot/uImage $DEST/output/sdcard/boot/

cp -R $DEST/linux-sunxi/output/lib/modules $DEST/output/sdcard/lib/
cp -R $DEST/linux-sunxi/output/lib/firmware/ $DEST/output/sdcard/lib/

cd $DEST/output/sdcard/lib/firmware
wget https://www.dropbox.com/s/o3evaiuidtg6xb5/ap6210.zip
unzip ap6210.zip
rm ap6210.zip
cd $DEST/
# cleanup 
rm $DEST/output/sdcard/usr/bin/qemu-arm-static 
# umount images 
umount $DEST/output/sdcard/ 
losetup -d /dev/loop1 
losetup -d /dev/loop0
# compress image 
gzip $DEST/output/*.raw