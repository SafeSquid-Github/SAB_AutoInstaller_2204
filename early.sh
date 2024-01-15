#!/bin/bash

#Declare associate arrays
declare -A DISK_NAME
declare -A MOUNT_TYPE
declare -A DISK_FS
declare -A DISK_MIN
declare -A DISK_MAX
declare -A DISK_PRIORITY
declare -A DISK_PERCENT
declare -A USE_DISK_SIZE 

#Get the list of attached storage device.
DISK_ATTACHED=$(lsblk -l | awk '/disk/ {print $1}' | wc -l)

#LV name for each partition.
DISK_NAME["/"]="root"
DISK_NAME["''"]="swap"
DISK_NAME["/home"]="home"
DISK_NAME["/opt/safesquid"]="opt+safesquid"
DISK_NAME["/usr/local/safesquid"]="usr+local+safesquid"
DISK_NAME["/var/lib/safesquid"]="var+lib+safesquid"
DISK_NAME["/var/cache/safesquid"]="var+cache+safesquid"
DISK_NAME["/var/www/safesquid"]="var+www+safesquid"
DISK_NAME["/var/db/safesquid"]="var+db+safesquid"
DISK_NAME["/var/log/safesquid"]="var+log+safesquid"
#Mount type for each partiton.
MOUNT_TYPE["/"]="mount"
MOUNT_TYPE["''"]="swap"
MOUNT_TYPE["/home"]="mount"
MOUNT_TYPE["/opt/safesquid"]="mount"
MOUNT_TYPE["/usr/local/safesquid"]="mount"
MOUNT_TYPE["/var/lib/safesquid"]="mount"
MOUNT_TYPE["/var/cache/safesquid"]="mount"
MOUNT_TYPE["/var/www/safesquid"]="mount"
MOUNT_TYPE["/var/db/safesquid"]="mount"
MOUNT_TYPE["/var/log/safesquid"]="mount"
#File system type for each partition.
DISK_FS["/"]="ext4"
DISK_FS["''"]="swap"
DISK_FS["/home"]="ext4"
DISK_FS["/opt/safesquid"]="ext4"
DISK_FS["/usr/local/safesquid"]="ext4"
DISK_FS["/var/lib/safesquid"]="ext4"
DISK_FS["/var/cache/safesquid"]="ext4"
DISK_FS["/var/www/safesquid"]="ext4"
DISK_FS["/var/db/safesquid"]="ext4"
DISK_FS["/var/log/safesquid"]="ext4"
##################################################
#DISK_MIN_
DISK_MIN["/"]=5120
DISK_MIN["''"]=2048
DISK_MIN["/home"]=5120
DISK_MIN["/opt/safesquid"]=512
DISK_MIN["/usr/local/safesquid"]=1024
DISK_MIN["/var/lib/safesquid"]=512
DISK_MIN["/var/cache/safesquid"]=1024
DISK_MIN["/var/www/safesquid"]=5120
DISK_MIN["/var/db/safesquid"]=2048
DISK_MIN["/var/log/safesquid"]=1024
#DISK_MAX_
DISK_MAX["/"]=-1
DISK_MAX["''"]=8192
DISK_MAX["/home"]=20480
DISK_MAX["/opt/safesquid"]=4096
DISK_MAX["/usr/local/safesquid"]=4096
DISK_MAX["/var/lib/safesquid"]=4096
DISK_MAX["/var/cache/safesquid"]=5120
DISK_MAX["/var/www/safesquid"]=15360
DISK_MAX["/var/db/safesquid"]=10240
DISK_MAX["/var/log/safesquid"]=-1
#DISK_PRIORITY_
DISK_PRIORITY["/"]=5
DISK_PRIORITY["''"]=2
DISK_PRIORITY["/home"]=4
DISK_PRIORITY["/opt/safesquid"]=1
DISK_PRIORITY["/usr/local/safesquid"]=1
DISK_PRIORITY["/var/lib/safesquid"]=2
DISK_PRIORITY["/var/cache/safesquid"]=2
DISK_PRIORITY["/var/www/safesquid"]=3
DISK_PRIORITY["/var/db/safesquid"]=2
DISK_PRIORITY["/var/log/safesquid"]=9

#Select the boot method.
SELECT_BOOT () {
#Based on the presence of /sys/firmware/efi file choose to boot either as UEFI or BIOS.
#/boot=2048 GB and /boot/efi=512M
    [ -e "/sys/firmware/efi" ] &&  sed -i 's/storage_UEFI:/storage:/' /autoinstall.yaml && BOOT_SIZE=$(( 2560 * 1024 * 1024 )) 
#/boot=2048 GB
    [ ! -e "/sys/firmware/efi" ] && sed -i 's/storage_BIOS:/storage:/' /autoinstall.yaml && BOOT_SIZE=$(( 2048 * 1024 * 1024 ))
}

#Get storage devices for LVM.
GET_STORAGE_DEVICE () {
#Check if attached storage devices are more than one.
    while read -r disk && [ "${DISK_ATTACHED}" != 1 ]
    do
#Append new disk key values to storage config.
cat <<- _EOF > /tmp/disk-${disk}
    -   ptable: gpt
        path: /dev/${disk}
        wipe: superblock
        preserve: false
        name: ''
        grub_device: false
        type: disk
        id: ${disk}
    -   device: ${disk}
        size: -1     
        wipe: superblock 
        flag: '' 
        preserve: false 
        grub_device: false 
        number: 1
        type: partition 
        id: disk-${disk}
_EOF
        sed -i "/.*id: additional-disks/r /tmp/disk-${disk}" /autoinstall.yaml
#Append new disk to be a part of LVM
cat <<- _EOF > /tmp/disk-${disk}
        - disk-${disk}
_EOF
        sed -i "/- lvm-disk/r /tmp/disk-${disk}" /autoinstall.yaml
    done < <(lsblk -l| awk '/disk/ {print $1}' | awk '(NR>1)' | sort -r)

#Remove id from autoinstall.yaml
    sed -i '/.*id: additional-disks/d' /autoinstall.yaml
}

#Create lvm code block for user data.
LV_CREATE () {
	> /tmp/storage
    DISK_N=0
	for LV in "${!DISK_NAME[@]}"
	do 
        (( DISK_N++ ))
cat <<- _EOF >> /tmp/storage
    -   name: ${DISK_NAME[${LV}]}
        volgroup: lvm_volgroup-0
        size: ${USE_DISK_SIZE[${LV}]}M
        wipe: superblock
        preserve: false
        path: /dev/safesquid-vg/${DISK_NAME[${LV}]}
        type: lvm_partition
        id: lvm_partition-${DISK_N}
    -   fstype: ${DISK_FS[${LV}]}
        volume: lvm_partition-${DISK_N}
        preserve: false
        type: format
        id: format-${DISK_N}
    -   path: ${LV}
        device: format-${DISK_N}
        type: ${MOUNT_TYPE[${LV}]}
        id: mount-${DISK_N}
_EOF
	done 
#Append the partition layout and remove the id from autoinstall.yaml file.
    sed -i "/.*id: LVM-partitions/r /tmp/storage" /autoinstall.yaml
    sed -i '/.*id: LVM-partitions/d' /autoinstall.yaml
}

#Get total disk size for available storage device
GET_TOTAL_DISK_SIZE () {
    DISK_SIZE=( $(lsblk -b | awk '/disk/ {print $4}') )
    TOTAL_DISK_SIZE=0
    for ((i = 0 ; i < "${#DISK_SIZE[*]}" ; i++))
    do
        (( TOTAL_DISK_SIZE+="${DISK_SIZE[i]}" ))
    done
#Total disk size less boot size which is either 2048 or 2560 depending upon boot
    TOTAL_DISK_SIZE="$(( "${TOTAL_DISK_SIZE}" - "${BOOT_SIZE}" ))"
}

ALLOT_MINIMUM_DISK () {
    
    TOTAL_MIN_DISK=0
    for LV in "${!DISK_MIN[@]}"
    do
        USE_DISK_SIZE[${LV}]=${DISK_MIN[${LV}]}
        (( TOTAL_MIN_DISK+=${DISK_MIN[${LV}]} ))
#If available total disk is less than total minumum disk space then return function.
        [[ $(( $TOTAL_DISK_SIZE / 1024 / 1024 )) -lt $TOTAL_MIN_DISK ]] && echo "Total Disk Size less than required Minimum" && exit
    done
}

DISK_AVAIL_TO_USE () {
#check for available disk storage.
    DISK_SPACE_UTILIZED=0
    for TOTAL_USED_SPACE in ${USE_DISK_SIZE[@]}
    do
        (( DISK_SPACE_UTILIZED+=TOTAL_USED_SPACE ))
    done
#2560/2048 will be used for /boot depends upon boot type
    AVAILABLE_DISK="$(( $(( TOTAL_DISK_SIZE / 1024 / 1024 )) - DISK_SPACE_UTILIZED ))"
} 

#Get the disk size which is smaller than the disk maximum; else use disk maximum.
MIN()
{
    [[ $2 == -1  ]] && echo $1 && return
    [[ $1 -le $2 ]] && echo $1 && return
    echo $2
}

#Sort priority in ascending order
GET_DISK_PRIORITY () {
# Calculate the total priority weight
    TOTAL_PRIORITY=0
    for key in "${!DISK_PRIORITY[@]}"
    do 
        (( TOTAL_PRIORITY+=${DISK_PRIORITY[${key}]} ))
        echo "${DISK_PRIORITY[${key}]}" $key
    done
}

#Check if available disk is in negative set minimum disk for all storage.
ALLOT_DISK () {

    GET_DISK_PRIORITY
    USE_TOTAL_PRIORITY=$TOTAL_PRIORITY
    while read -r PRIORITY PARTITION 
    do 
        DISK_AVAIL_TO_USE
        [[ ${AVAILABLE_DISK} -le 512 ]] && return;
        ALLOT_REMAINIG_DISK=$(( $AVAILABLE_DISK * $PRIORITY / $USE_TOTAL_PRIORITY ))
        (( USE_TOTAL_PRIORITY-=$PRIORITY ))
        NEW_DISK_SIZE_OFFERED="$(( $ALLOT_REMAINIG_DISK + ${USE_DISK_SIZE[${PARTITION}]} ))"
        X=$(MIN ${NEW_DISK_SIZE_OFFERED} ${DISK_MAX[${PARTITION}]})
        USE_DISK_SIZE[${PARTITION}]=$X
    done < <(GET_DISK_PRIORITY | sort)
}

#Run MAIN function
MAIN () {

    SELECT_BOOT
    GET_STORAGE_DEVICE
    GET_TOTAL_DISK_SIZE
    ALLOT_MINIMUM_DISK
    ALLOT_DISK
    LV_CREATE
}

MAIN