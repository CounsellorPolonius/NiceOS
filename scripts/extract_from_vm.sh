#!/bin/bash

source ./.config.sh || exit 1

if [ -z "$DISTRO" ]; then
    echo "You need to specify extracting distribution from $BASE/distro_extractor, use one of"
    ls "$BASE/distro_extractor"
    dd "use \`export DISTRO=artix\` for example"
fi
if [ -z "$DISTRO_ISO" ]; then
    echo "You need to specify distribution install iso path"
    echo "use \`export DISTRO_ISO=/data/dwn/artix-base-openrc-20220123-x86_64.iso\` for example"
    echo " or "
    dd "use \`export DISTRO_ISO=/data/dwn/devuan_chimaera_4.0.0_amd64_minimal-live.iso\` for example"
fi


function boot_info_qemu() {
    echo "For future password prompt write $VM_PASS"
}
source "$BASE/distro_extractor/$DISTRO/inc.sh" || dd "File '$BASE/distro_extractor/$DISTRO/inc.sh' cannot be sourced"

function ssh_install() {
    [ -r "$NICE_PRESET_PATH/packages.${PM}.txt" ] || dd "No packages list for your preset and $DISTRO found ($NICE_PRESET_PATH/packages.${PM}.txt)"
    scp -o LogLevel=Error -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -P "$2" "$BASE/distro_extractor/$DISTRO/install.sh" "$NICE_PRESET_PATH/packages.${PM}.txt" "$VM_USER@$1:/tmp/"
    echo "${VM_PASS:-''}" | ssh -o LogLevel=Error -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no "$VM_USER@$1" -p "$2" 'sudo --stdin bash /tmp/install.sh'
}

function host_shell_wait() {
    echo "Welcome back to user host shell"
    echo "Waiting for virtual machine to shutdown for max 60sec"
    for i in {1..20}
    do
        sleep 3
        echo "Waiting..."
        ps auxf | grep -- "$1" | grep -v grep > /dev/null || break
    done
}

function from_qemu() {
    qemu-img create -f raw "$NICE_EXTRACT_DISTRO_HDD_IMAGE_PATH" "${DISK_SIZE_GB}G"
    qemu-system-x86_64 \
        -cdrom "$DISTRO_ISO" -drive file="$NICE_EXTRACT_DISTRO_HDD_IMAGE_PATH",format=raw,cache=unsafe -m "$QEMU_RAM" \
        -net user,hostfwd=tcp::2201-:22 -net nic -enable-kvm -cpu host -smp "$QEMU_PROCESSOR_CORES" &

    boot_info
    boot_info_qemu

    echo "If all done press enter here"
    read

    ssh_install localhost 2201
    host_shell_wait "-cdrom $DISTRO_ISO"
}

function from_virtualbox() {
    VIRTUAL_BOX_VM_ROOT="$VIRTUAL_BOX_VMS_ROOT/$DISTRO"
    echo "Startup virtual machine named '$DISTRO' saved at $VIRTUAL_BOX_VM_ROOT"
    echo "with distribution installation CD connected"
    echo "one VDI hard disk connected (min ${DISK_SIZE_GB}GB), one bridged adapter network enabled"
    boot_info

    echo "Run ip addr | grep eth0 | grep inet"
    echo "Type here local ip address of bridge network eth0 (inet brd) and hit enter"
    read IP_ADDRESS
    echo "$IP_ADDRESS"

    ssh_install "$IP_ADDRESS" 22
    host_shell_wait "comment $DISTRO"

    [ -r "$VIRTUAL_BOX_VM_ROOT/$DISTRO.vdi" ] || dd "Cannot find VDI '$VIRTUAL_BOX_VM_ROOT/$DISTRO.vdi'"
    echo "Extracting virtual disk image"
    VBoxManage clonehd --format RAW "$VIRTUAL_BOX_VM_ROOT/$DISTRO.vdi" "$NICE_EXTRACT_DISTRO_HDD_IMAGE_PATH"
}

rm -f "$NICE_EXTRACT_DISTRO_HDD_IMAGE_PATH"
if [[ -n "$1" && "$1" = "virtualbox" ]]; then
    from_virtualbox
else
    from_qemu
fi
