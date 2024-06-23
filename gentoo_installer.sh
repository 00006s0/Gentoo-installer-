#!/bin/bash

# Exit on any error
set -e

# Variables
DISK="/dev/sdc"
STAGE3="stage3-amd64-latest.tar.xz"
MOUNTPOINT="/mnt/gentoo"
MIRROR="http://ftp.halifax.rwth-aachen.de/gentoo/releases/amd64/autobuilds/current-stage3-amd64/"
CHROOT_SCRIPT="/mnt/gentoo/chroot_script.sh"

# Update system clock
echo "Updating system clock..."
ntpd -q -g

# Partition the disk
echo "Partitioning the disk..."
parted -s "$DISK" mklabel msdos
parted -s "$DISK" mkpart primary ext4 1MiB 100%
parted -s "$DISK" set 1 boot on

# Format the partitions
echo "Formatting the partitions..."
mkfs.ext4 "${DISK}1"

# Mount the partitions
echo "Mounting the partitions..."
mount "${DISK}1" "$MOUNTPOINT"

# Download and extract stage3
echo "Downloading and extracting stage3..."
wget "$MIRROR/$STAGE3" -P "$MOUNTPOINT"
tar xpvf "$MOUNTPOINT/$STAGE3" --xattrs-include='*.*' --numeric-owner -C "$MOUNTPOINT"

# Copy DNS info
echo "Copying DNS info..."
cp -L /etc/resolv.conf "$MOUNTPOINT/etc/"

# Mount necessary filesystems
echo "Mounting necessary filesystems..."
mount -t proc /proc "$MOUNTPOINT/proc"
mount --rbind /sys "$MOUNTPOINT/sys"
mount --make-rslave "$MOUNTPOINT/sys"
mount --rbind /dev "$MOUNTPOINT/dev"
mount --make-rslave "$MOUNTPOINT/dev"

# Create chroot script
cat << 'EOF' > "$CHROOT_SCRIPT"
#!/bin/bash
source /etc/profile
export PS1="(chroot) $PS1"

# Set the timezone
echo "Setting the timezone..."
echo "Europe/Berlin" > /etc/timezone
emerge --config sys-libs/timezone-data

# Set locale
echo "Setting locale..."
echo 'en_US.UTF-8 UTF-8' >> /etc/locale.gen
locale-gen
echo 'LANG="en_US.UTF-8"' > /etc/env.d/02locale
env-update && source /etc/profile

# Set binary package host
echo "Setting binary package host..."
echo 'PORTAGE_BINHOST="https://isshoni.org/binhost"' >> /etc/portage/make.conf

# Install the Gentoo base system
echo "Installing the Gentoo base system with binaries..."
emerge-webrsync
emerge --sync
emerge -gK gentoo-sources

# Configure the kernel
echo "Configuring the kernel..."
cd /usr/src/linux
make menuconfig
make && make modules_install
make install

# Install necessary packages
echo "Installing necessary packages..."
emerge -gK sys-kernel/genkernel
genkernel all

# Install bootloader
echo "Installing bootloader..."
emerge -gK sys-boot/grub
grub-install --target=i386-pc /dev/sdc
grub-mkconfig -o /boot/grub/grub.cfg

# Set root password
echo "Setting root password..."
passwd

# Exit chroot
exit
EOF

# Make the chroot script executable and run it in chroot
chmod +x "$CHROOT_SCRIPT"
chroot "$MOUNTPOINT" /bin/bash -c "/chroot_script.sh"

# Cleanup
echo "Cleaning up..."
rm "$MOUNTPOINT/$STAGE3"
rm "$CHROOT_SCRIPT"

# Unmount filesystems
echo "Unmounting filesystems..."
umount -l "$MOUNTPOINT/dev"{,/shm,/pts}
umount -R "$MOUNTPOINT"

echo "Installation complete. Please reboot."
