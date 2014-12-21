#!/bin/bash

[[ -z $DEBUG ]] || set -o xtrace

set -o nounset
set -o errexit

DEBIAN_VERSION="${DEBIAN_VERSION:-wheezy}"
DEBIAN_ARCH="${DEBIAN_ARCH:-i386}"
DEBIAN_MIRROR="${DEBIAN_MIRROR:-http://ftp.pl.debian.org}"

TEMP="$( mktemp -d )"
VM_NAME="${DEBIAN_VERSION}-${DEBIAN_ARCH}-$( date +'%Y%m%d%H%M%S' )"
NETBOOT_URL="${DEBIAN_MIRROR}/debian/dists/${DEBIAN_VERSION}/main/installer-${DEBIAN_ARCH}/current/images"
PXE_TFTP_PREFIX="${TEMP}/boot"
PXE_BOOT_FILE="pxelinux.0"


log() {
	local prefix="[$(date +%Y/%m/%d\ %H:%M:%S)]:"
	echo "${prefix} $*" >&2
} 

trap 'rm -rf "${TEMP}" "${VM_NAME}"; exit $?' EXIT INT TERM

mkdir -p "${PXE_TFTP_PREFIX}"

log "INFO" "Preparing netboot image."

NETBOOT_SHA256SUM="$( wget -q "${NETBOOT_URL}/SHA256SUMS" -O - \
	| grep 'netboot/netboot.tar.gz' \
	| cut -d' ' -f1 )"

wget -q "${NETBOOT_URL}/netboot/netboot.tar.gz" -O "${TEMP}/netboot.tar.gz"

NETBOOT_DWL_SHA256SUM="$( sha256sum "${TEMP}/netboot.tar.gz" | cut -d' ' -f1 )"

if [ "${NETBOOT_SHA256SUM}" != "${NETBOOT_DWL_SHA256SUM}" ]; then
	echo "ERROR: SHA256SUM does not match!"
	exit 1
fi

tar xfz "${TEMP}/netboot.tar.gz" -C "${PXE_TFTP_PREFIX}"

gunzip "${PXE_TFTP_PREFIX}/debian-installer/${DEBIAN_ARCH}/initrd.gz"

echo "preseed.cfg" | cpio -ovA -H newc -F "${PXE_TFTP_PREFIX}/debian-installer/${DEBIAN_ARCH}/initrd" >/dev/null 2>&1
echo "late_command.sh" | cpio -ovA -H newc -F "${PXE_TFTP_PREFIX}/debian-installer/${DEBIAN_ARCH}/initrd" >/dev/null 2>&1 

gzip "${PXE_TFTP_PREFIX}/debian-installer/${DEBIAN_ARCH}/initrd"

cat <<EOF > ${PXE_TFTP_PREFIX}/pxelinux.cfg/default
default auto
prompt 0
timeout 0
label auto
	kernel debian-installer/${DEBIAN_ARCH}/linux
	append priority=critical file=/preseed.cfg hostname=${VM_NAME} keymap=pl locale=pl_PL auto vga=788 initrd=debian-installer/${DEBIAN_ARCH}/initrd.gz
EOF

log "INFO" "Creating VM."

VBoxManage createvm \
	--name "${VM_NAME}" \
	--ostype Debian_64 \
	--register >/dev/null 2>&1

VBoxManage modifyvm "${VM_NAME}" \
	--memory 512 \
	--nic1 nat \
	--nictype1 Am79C970A \
	--boot1 net \
	--vram 16 \
	--pae off >/dev/null 2>&1

VBoxManage storagectl "${VM_NAME}" \
	--name "SATA Controller" \
	--add sata \
	--controller IntelAhci \
	--portcount 1 >/dev/null 2>&1

VBoxManage createhd \
	--filename "${VM_NAME}/${VM_NAME}.vdi" \
	--size 32768 >/dev/null 2>&1

VBoxManage setextradata "${VM_NAME}" \
	"VBoxInternal/Devices/pcnet/0/LUN#0/Config/TFTPPrefix" \
	"${PXE_TFTP_PREFIX}" >/dev/null 2>&1

VBoxManage setextradata "${VM_NAME}" \
	"VBoxInternal/Devices/pcnet/0/LUN#0/Config/BootFile" \
	"$PXE_BOOT_FILE" >/dev/null 2>&1

VBoxManage storageattach "${VM_NAME}" \
	--storagectl "SATA Controller" \
	--port 0 \
	--type hdd \
	--medium "${VM_NAME}/${VM_NAME}.vdi" >/dev/null 2>&1

log "INFO" "Booting VM. This may take a few minutes..."

VBoxHeadless -s "${VM_NAME}" \
	-v off >/dev/null 2>&1

VBoxManage modifyvm "${VM_NAME}" \
	--boot1 disk >/dev/null 2>&1

log "INFO" "Creating vagrant box."

vagrant package --base "${VM_NAME}" --output "${VM_NAME}.box" >/dev/null 2>&1

log "INFO" "Cleaning up."

VBoxManage unregistervm "${VM_NAME}" --delete >/dev/null 2>&1

log "INFO" "Done."

