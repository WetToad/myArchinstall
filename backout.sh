#!/bin/bash

# File: backout.sh
# Desc: Testing script to revert partitions/LVMs and backout anychanges made to return to a blank state.
# Author: Joseph Mowery
# Email: mowery.joseph@outlook.com

# Turn off all swap
swapoff -a

# Unmount every subvolume and partition
umount /mnt/opt
umount /mnt/var
umount /mnt/home
umount /mnt/boot
umount /mnt/efi
umount -R /mnt

# Deactivate the volume group
lvchange -an /dev/vg0/btrfs
vgchange -an vg0

# Close LUKS containers
cryptsetup close swap_crypt
cryptsetup close lvm_crypt

# Clear disk, force and on all partitions
wipefs -fa /dev/nvme0n1