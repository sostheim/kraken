#!/bin/bash
# wget -O ./hack/get-coreos.sh https://raw.githubusercontent.com/coreos/coreos-baremetal/master/scripts/get-coreos
# USAGE: ./hack/get-coreos.sh
# USAGE: ./hack/get-coreos.sh channel version dest
set -eou pipefail

CHANNEL=${1:-"alpha"}
VERSION=${2:-"1109.1.0"}
DEST_DIR=${3:-"$PWD/bootcfg/assets"}
DEST=$DEST_DIR/coreos/$VERSION
BASE_URL=https://$CHANNEL.release.core-os.net/amd64-usr/$VERSION

# check channel/version exist based on the header response
curl -s -I $BASE_URL/coreos_production_pxe.vmlinuz | awk '/2.0 200/ {found++} /1.1 200/ {found++} /1.1 301/ {found++} END { if (found<1) { print "Channel or Version not found"; exit 1 }}'

if [ ! -d "$DEST" ]; then
  echo "Creating directory $DEST"
  mkdir -p $DEST
fi

echo "Downloading CoreOS $CHANNEL $VERSION images and sigs to $DEST"

echo "CoreOS Image Signing Key"
curl -# https://coreos.com/security/image-signing-key/CoreOS_Image_Signing_Key.asc -o $DEST/CoreOS_Image_Signing_Key.asc
gpg --import < "$DEST/CoreOS_Image_Signing_Key.asc" || true

# PXE kernel and sig
echo "coreos_production_pxe.vmlinuz..."
curl -# $BASE_URL/coreos_production_pxe.vmlinuz -o $DEST/coreos_production_pxe.vmlinuz
echo "coreos_production_pxe.vmlinuz.sig"
curl -# $BASE_URL/coreos_production_pxe.vmlinuz.sig -o $DEST/coreos_production_pxe.vmlinuz.sig

# PXE initrd and sig
echo "coreos_production_pxe_image.cpio.gz"
curl -# $BASE_URL/coreos_production_pxe_image.cpio.gz -o $DEST/coreos_production_pxe_image.cpio.gz
echo "coreos_production_pxe_image.cpio.gz.sig"
curl -# $BASE_URL/coreos_production_pxe_image.cpio.gz.sig -o $DEST/coreos_production_pxe_image.cpio.gz.sig

# Install image
echo "coreos_production_image.bin.bz2"
curl -# $BASE_URL/coreos_production_image.bin.bz2 -o $DEST/coreos_production_image.bin.bz2
echo "coreos_production_image.bin.bz2.sig"
curl -# $BASE_URL/coreos_production_image.bin.bz2.sig -o $DEST/coreos_production_image.bin.bz2.sig

# verify signatures
gpg --verify $DEST/coreos_production_pxe.vmlinuz.sig
gpg --verify $DEST/coreos_production_pxe_image.cpio.gz.sig
gpg --verify $DEST/coreos_production_image.bin.bz2.sig
