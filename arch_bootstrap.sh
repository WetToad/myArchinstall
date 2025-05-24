#!/bin/bash

# File: arch_bootstrap.sh
# Desc: A heavily targeted Arch Linux install script to bootstrap a machine from scratch to operable.
# Author: Joseph Mowery
# Email: mowery.joseph@outlook.com

set -euo pipefail

# Generate ANSI escape sequences dynamically using Portable Terminal Control (tput)
if [ -t 1 ]; then
    RED=$(tput setaf 1)
    GREEN=$(tput setaf 2)
    YELLOW=$(tput setaf 3)
    BLUE=$(tput setaf 4)
    BOLD=$(tput bold)
    RESET=$(tput sgr0)
else
    # No colors if redirected
    RED=""
    GREEN=""
    YELLOW=""
    BLUE=""
    BOLD=""
    RESET=""
fi

echo "${BOLD}${RED}WARNING: Continuing with this script will completely erase all data on the system.${RESET}"
read -rp "${RED}Type 'ERASE' to continue and accept... ${RESET}" confirm
[[ "$confirm" != "ERASE" ]] && exit 1

read -rsp "Enter LUKS passphrase: " luks_pass && echo
read -rsp "Verify passphrase: " luks_verify && echo
[[ "$luks_pass" != "$luks_verify" ]] && echo "Passphrase mismatch." && exit 1
unset luks_verify

# Sync time, required for HTTPS otherwise requests could be faulty
timedatectl set-ntp true

# Clear and format drive as GPT, which is the standard for UEFI
wipefs --all /dev/nvme0n1
parted --script /dev/nvme0n1 mklabel gpt

# Partition layout (1TB NVMe):
# p1: EFI System Partition (FAT32, 1GiB)
# p2: /boot (ext4, 1GiB)
# p3: swap (encrypted with fixed key, ~65GiB)
# p4: LVM container (remainder of disk)

# Create ESP partition, starts at 1MiB for wider firmware compatability/per UEFI specification
parted --script /dev/nvme0n1 \
    mkpart ESP fat32 1MiB 1025MiB \
    name 1 ESP \
    set 1 esp on

# Create boot partition
parted --script /dev/nvme0n1 \
    mkpart primary ext4 1025MiB 2049MiB \
    name 2 BOOT

# Create swap partition, allocate ~65GiB to allow for hibernation
parted --script /dev/nvme0n1 \
    mkpart primary linux-swap 2049MiB 68657MiB \
    name 3 SWAP

# Create LVM partition
parted --script /dev/nvme0n1 \
    mkpart primary 68657MiB 100% \
    name 4 LVM

# Prepare filesystem
mkfs.fat -F32 /dev/nvme0n1p1 # ESP
mkfs.ext4 /dev/nvme0n1p2     # /boot

# Generate fixed swap keyfile (kept in /root for initramfs)
dd if=/dev/urandom of=/root/swap.key bs=4096 count=1
chmod 600 /root/swap.key

# Encrypt swap with fixed key
cryptsetup luksFormat --type luks2 /dev/nvme0n1p3 \
    --batch-mode --key-file /root/swap.key

# Encrypt LVM PV with passphrase
echo -n "$luks_pass" | cryptsetup luksFormat --type luks2 /dev/nvme0n1p4 -
echo -n "$luks_pass" | cryptsetup open /dev/nvme0n1p4 lvm_crypt -

# Enroll YubiKey for FIDO2 on root and swap partitions
echo '>>> Enroll FIDO2 for root (touch YubiKey when prompted)'
systemd-cryptenroll --fido2-device=auto /dev/nvme0n1p4

echo ">>> Verifing FIDO2 enrollment for LVM partition:"
systemd-cryptenroll --fido2-device=auto /dev/nvme0n1p4 --fido2-credential-algorithm=es256 --fido2-with-user-presence=yes

echo '>>> Enroll FIDO2 for swap (touch YubiKey when prompted)'
systemd-cryptenroll \
    --fido2-device=auto \
    --unlock-key-file=/root/swap.key \
    /dev/nvme0n1p3

echo ">>> Verifing FIDO2 enrollment for swap partition:"
systemd-cryptenroll --fido2-device=auto /dev/nvme0n1p3 --fido2-credential-algorithm=es256 --fido2-with-user-presence=yes

# Initialive LVM and mark /dev/mapper/lvm_crypt (LUKS‐locked block device) as an LVM Physical Volume
pvcreate /dev/mapper/lvm_crypt

# Create VG(0) that includes the PV that was just initialized
vgcreate vg0 /dev/mapper/lvm_crypt

# Allocated remaining space in vg0 to a new logical volume named btrfs, one LV allows for single encryption when using btrfs
lvcreate -l 100%FREE vg0 -n btrfs

# Format the fs that sits on top the LV as btrfs and mount TEMPORARILY to make subvolumes below
mkfs.btrfs -L BTRFS /dev/vg0/btrfs
mount /dev/vg0/btrfs /mnt

# Subvolumes Layout:
# root: Does an update break the system? Only need to roll back the root dir
# home: Separate personal files from system state for independent backup/restore cycles
#  var: Isolate logs, caches, and databases that change frequently and can grow large
#  opt: Manage third-party software independently from core system packages
btrfs subvolume create /mnt/@
btrfs subvolume create /mnt/@home
btrfs subvolume create /mnt/@var
btrfs subvolume create /mnt/@opt

umount /mnt

# Mount subvolumes with recommended options
mount -o noatime,compress=zstd,ssd,space_cache=v2,subvol=@ /dev/vg0/btrfs /mnt
mkdir -p /mnt/{boot,efi,home,var,opt}

# Mount each subvolume with options inherited
mount -o subvol=@home /dev/vg0/btrfs /mnt/home
mount -o subvol=@var /dev/vg0/btrfs /mnt/var
mount -o subvol=@opt /dev/vg0/btrfs /mnt/opt

mount /dev/nvme0n1p2 /mnt/boot # ext4 /boot
mount /dev/nvme0n1p1 /mnt/efi  # ESP

# Base system packages for minimal setup
packages=(
    amd-ucode                    # AMD microprossesor firmware and security updates
    arch-install-scripts         # Needed for genfstab utility while chrooting
    base                         # Recommended for minimal system
    base-devel                   # Package group containing common build tools: gcc, make, binutils (Required for AUR and makepkg)
    btrfs-progs                  # User-space utilities for managing btrfs filesystems
    fwupd                        # Automate firmware updates
    git                          # Version control (Required to clone libu2f-host, which is recommended when using pcsc)
    iwd                          # iNet Wireless Daemon for WiFi connections using WPA
    less                         # Text utility for scrolling through text based files via terminal
    libfido2                     # Support for FIDO-U2F operations (Prefered over libuf2-host which is deprecated)
    linux                        # The Linux kernel
    linux-firmware               # Firmware blobs for Wi-Fi, GPUs, etc.
    lvm2                         # Logical Volume Manager utilities: pvcreate, vgcreate, lvcreate
    mkinitcpio-systemd-tool      # Provisioning tool for initramfs when using systemd
    mkinitcpio                   # Bash script to create the initial ramdisk on boot
    pcsc-tools                   # PC/SC smartcard utilities (pcsc_scan, etc.)
    sbctl                        # Secure Boot key management and signing
    sof-firmware                 # Open source audio drivers
    vim                          # Open source text editor
    yubikey-manager              # Configure YubiKey
    yubikey-full-disk-encryption # Integrate YubiKey with LUKS (ykfde)
)

pacstrap /mnt --noconfirm "${packages[@]}"

# Copy swap.key into the to target system (must occur after pacstrap)
install -Dm600 /root/swap.key /mnt/root/swap.key

# Generate fstab table for persistant mounting
genfstab -U /mnt >>/mnt/etc/fstab

# Create minimal vconsole.conf file that mkinitcpio looks for
cat >/mnt/etc/vconsole.conf <<EOF
KEYMAP=us
FONT=lat9w-16
EOF

# Bind mounts for chroot
to_mount=(dev dev/pts proc sys sys/firmware/efi/efivars)
for m in "${to_mount[@]}"; do
    mkdir -p /mnt/$m
    mount --bind /$m /mnt/$m
done

read -rsp "Enter root password: " ROOT_PASS && echo
read -rsp "Verify password: " ROOT_PASS2 && echo
[[ "$ROOT_PASS" != "$ROOT_PASS2" ]] && echo "Passphrase mismatch." && exit 1

# Chroot to start new bash shell with /mnt as root to modify target system
arch-chroot /mnt /bin/bash <<EOF
set -euo pipefail

printf 'root:%q\n' "${ROOT_PASS}" | chpasswd
unset ROOT_PASS ROOT_PASS2

# Create builder user for non-root AUR builds
useradd -m builder

# Build mkinitcpio-openswap as non-root
runuser -u builder -- bash -lc '
  cd ~ && git clone https://aur.archlinux.org/mkinitcpio-openswap.git && \
  cd mkinitcpio-openswap && makepkg -s --noconfirm'

# Install the built openswap package into the system
pacman -U --noconfirm /home/builder/mkinitcpio-openswap/*.pkg.tar.zst

# Enable/start pcsc daemon
systemctl enable pcscd
systemctl start  pcscd

# Create your Platform, KEK, and DB keys
sbctl create-keys

# Enroll keys into firmware (use Microsoft keys for compatibility)
sbctl enroll-keys --microsoft

cryptsetup open /dev/nvme0n1p3 swap_crypt --key-file /root/swap.key
mkswap -L SWAP -U "$(uuidgen)" /dev/mapper/swap_crypt
swapon /dev/mapper/swap_crypt

# Header UUID, for crypttab:
LUKS_HEADER_UUID=$(cryptsetup luksUUID /dev/nvme0n1p3)
# Filesystem UUID, for fstab:
SWAP_FS_UUID=$(blkid -s UUID -o value /dev/mapper/swap_crypt)
# Update crypttab for FIDO2, swap must come first so the resume hook can find the hibernation swap
printf 'swap_crypt UUID=%s /root/swap.key luks,swap\n' "$(cryptsetup luksUUID /dev/nvme0n1p3)" >> /etc/crypttab
printf 'lvm_crypt UUID=%s none luks,fido2-device=auto\n' "$(blkid -s UUID -o value /dev/nvme0n1p4)" >> /etc/crypttab

cp /etc/crypttab /etc/crypttab.initramfs

genfstab -U / > /etc/fstab

# Configure mkinitcpio for systemd + sd-encrypt
sed -i 's/^MODULES=.*/MODULES=(usbhid)/' /etc/mkinitcpio.conf
# HOOKS – in exactly this order:
#  base, systemd, autodetect, keyboard, sd-vconsole, modconf
#  block, sd-encrypt  
#  openswap (AUR-provided swap‐unlock hook)
#  resume   (systemd resume hook which needs swap unlocked)  
#  sd-lvm2  (systemds LVM2 hook which needs luks+swap unlocked)  
#  btrfs    (filesystems hook for btrfs) 
#  filesystems, fsck
sed -i 's/^HOOKS=.*/HOOKS=(base systemd autodetect modconf block sd-vconsole keyboard sd-encrypt openswap resume lvm2 btrfs filesystems fsck)/' /etc/mkinitcpio.conf
sed -i 's|^FILES=.*|FILES=(/usr/lib/libfido2.so.1 /etc/crypttab.initramfs /root/swap.key)|' /etc/mkinitcpio.conf
mkinitcpio -P

# GRUB config for FIDO2
pacman -S --noconfirm grub efibootmgr
#sed -i 's|^GRUB_CMDLINE_LINUX=.*|GRUB_CMDLINE_LINUX="rd.luks.name=UUID=$(blkid -s UUID -o value /dev/nvme0n1p4)=lvm_crypt rd.luks.options=lvm_crypt=fido2-device=auto rd.luks.name=UUID=$(blkid -s UUID -o value /dev/nvme0n1p3)=swap_crypt rd.luks.options=swap_crypt=/root/swap.key root=UUID=$(blkid -s UUID -o value /dev/mapper/vg0-btrfs) rootflags=subvol=@ resume=/dev/mapper/swap_crypt"|' /etc/default/grub
sed -i 's|^GRUB_CMDLINE_LINUX=.*|GRUB_CMDLINE_LINUX="rd.luks.name=UUID=$(blkid -s UUID -o value /dev/nvme0n1p4)=lvm_crypt rd.luks.options=lvm_crypt=fido2-device=auto root=UUID=$(blkid -s UUID -o value /dev/mapper/vg0-btrfs) rootflags=subvol=@ resume=/dev/mapper/swap_crypt"|' /etc/default/grub

# Tell GRUB efi is not in /boot/efi but is located at /efi instead
grub-install --target=x86_64-efi --efi-directory=/efi --bootloader-id=GRUB --removable
grub-mkconfig -o /boot/grub/grub.cfg

# Sign keys for bootloader and kernel images
sbctl sign -s /efi/EFI/BOOT/BOOTX64.EFI
sbctl sign -s /boot/vmlinuz-linux

# Locale & timezone
ln -sf /usr/share/zoneinfo/America/New_York /etc/localtime
sed -i 's/^#en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

EOF

# Cleanup
rm /root/swap.key
swapoff -a
umount -R /mnt

# 2. Deactivate the LVM volume group
vgchange -an vg0

# 3. Close the LUKS mappings
cryptsetup luksClose swap_crypt
cryptsetup luksClose lvm_crypt

echo "${GREEN}Installation complete. Reboot for system changes to take effect."
