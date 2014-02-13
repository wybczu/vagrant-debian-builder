#!/bin/sh

set -e

[[ -z $DEBUG ]] || set -x

DEBIAN_VERSION="wheezy"
DEBIAN_ARCH="i386"
DEBIAN_MIRROR="http://ftp.pl.debian.org"

# --

TEMP="$( mktemp -d )"
VM_NAME="${DEBIAN_VERSION}-${DEBIAN_ARCH}-$( date +'%Y%m%d%H%M%S' )"
NETBOOT_URL="${DEBIAN_MIRROR}/debian/dists/${DEBIAN_VERSION}/main/installer-${DEBIAN_ARCH}/current/images"
PXE_TFTP_PREFIX="${TEMP}/boot"
PXE_BOOT_FILE="pxelinux.0"

trap 'rm -rf "${TEMP}" "${VM_NAME}"; exit $?' EXIT INT TERM

mkdir -p ${PXE_TFTP_PREFIX}

NETBOOT_SHA256SUM="$( wget -q ${NETBOOT_URL}/SHA256SUMS -O - \
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

echo "preseed.cfg" | cpio -ovA -H newc -F "${PXE_TFTP_PREFIX}/debian-installer/${DEBIAN_ARCH}/initrd"
echo "late_command.sh" | cpio -ovA -H newc -F "${PXE_TFTP_PREFIX}/debian-installer/${DEBIAN_ARCH}/initrd" 

gzip "${PXE_TFTP_PREFIX}/debian-installer/${DEBIAN_ARCH}/initrd"

cat <<EOF > ${PXE_TFTP_PREFIX}/pxelinux.cfg/default
default auto
prompt 0
timeout 0
label auto
	kernel debian-installer/${DEBIAN_ARCH}/linux
	append priority=critical file=/preseed.cfg hostname=${VM_NAME} keymap=pl locale=pl_PL auto vga=788 initrd=debian-installer/${DEBIAN_ARCH}/initrd.gz
EOF

VBoxManage createvm \
	--name "${VM_NAME}" \
	--ostype Debian_64 \
	--register

VBoxManage modifyvm "${VM_NAME}" \
	--memory 512 \
	--nic1 nat \
	--nictype1 Am79C970A \
	--boot1 net \
	--vram 16 \
	--pae off

VBoxManage storagectl "${VM_NAME}" \
	--name "SATA Controller" \
	--add sata \
	--controller IntelAhci \
	--portcount 1

VBoxManage createhd \
	--filename "${VM_NAME}/${VM_NAME}.vdi" \
	--size 32768

VBoxManage setextradata "${VM_NAME}" \
	"VBoxInternal/Devices/pcnet/0/LUN#0/Config/TFTPPrefix" \
	"${PXE_TFTP_PREFIX}"

VBoxManage setextradata "${VM_NAME}" \
	"VBoxInternal/Devices/pcnet/0/LUN#0/Config/BootFile" \
	"$PXE_BOOT_FILE"

VBoxManage storageattach "${VM_NAME}" \
	--storagectl "SATA Controller" \
	--port 0 \
	--type hdd \
	--medium "${VM_NAME}/${VM_NAME}.vdi"

VBoxHeadless -s "${VM_NAME}" \
	-v off

VBoxManage modifyvm "${VM_NAME}" \
	--boot1 disk

vagrant package --base "${VM_NAME}" --output "${VM_NAME}.box"

VBoxManage unregistervm "${VM_NAME}" --delete


