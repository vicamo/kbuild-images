ARG SERIES=devel
FROM ubuntu:$SERIES

ARG SERIES

RUN set -xe; \
	apt-get update --quiet; \
	apt-get install --no-install-recommends --yes \
		ca-certificates \
		python3 \
		python3-yaml \
		wget \
	;

RUN --mount=type=bind,source=kteam-tools,target=/opt/canonical/kteam-tools <<EOT
#!/bin/bash

CDIR=/opt/canonical/kteam-tools/chroot-setup
source "${CDIR}/scripts/chroot-defs.conf"

set -x

ARCH=$(dpkg --print-architecture)

# Ensure we have the extention PPA key and configuration.
get_apt_trusted "$SERIES"
[ -z "${APT_TRUSTED}" ] || \
    cp "${CDIR}/scripts/${APT_TRUSTED}" /etc/apt/trusted.gpg.d

write_mirror $SERIES ${ARCH} /etc/apt/sources.list.new
mv /etc/apt/sources.list.new /etc/apt/sources.list

echo "deb http://ppa.launchpad.net/canonical-kernel-team/builder-extra/ubuntu $SERIES main" \
    | tee /etc/apt/sources.list.d/canonical-kernel-team-ubuntu-builder-extra-$SERIES.list

# Enable retry logic for apt up to 10 times
echo "APT::Acquire::Retries \"10\";" > /etc/apt/apt.conf.d/80-retries

# If the user supplied an http_proxy when building this chroot, copy that
# configuration over into the apt configuration for the chroot.
if [ "${http_proxy}" != '' ]
then
  echo "Acquire::http { Proxy \"${http_proxy}\"; };" \
      | tee /etc/apt/apt.conf.d/01proxy-from-http_proxy
fi

export DEBIAN_FRONTEND=noninteractive

get_build_dep "$SERIES"
echo "Build dep: ${BUILD_DEP}"

get_build_arches "$SERIES"
echo "Build architectures: ${BUILD_ARCHES}"

# No longer calls into chroot-defs.conf defined functions. Turn on errors.
set -e

ADDPKG="fakeroot vim git-core devscripts lzop u-boot-tools patchutils"

if [ "${ARCH}" = "amd64" ]; then \
  for arch in ${BUILD_ARCHES}; do \
    case "${arch}" in \
      arm64)   pkgs="gcc-aarch64-linux-gnu libc6-dev-arm64-cross" ;;
      armel)   pkgs="gcc-arm-linux-gnueabi g++-arm-linux-gnueabi libc6-dev-armel-cross" ;;
      armhf)   pkgs="gcc-arm-linux-gnueabihf g++-arm-linux-gnueabihf libc6-dev-armhf-cross" ;;
      i386)    pkgs="gcc-i686-linux-gnu libc6-dev-i386-cross" ;;
      powerpc) pkgs="gcc-powerpc-linux-gnu g++-powerpc-linux-gnu libc6-dev-powerpc-cross" ;;
      ppc64el) pkgs="gcc-powerpc64le-linux-gnu libc6-dev-ppc64el-cross" ;;
      riscv64) pkgs="gcc-riscv64-linux-gnu libc6-dev-riscv64-cross" ;;
      s390x)   pkgs="gcc-s390x-linux-gnu libc6-dev-s390x-cross" ;;
    esac

    ADDPKG="${ADDPKG} ${pkgs}"
    echo "Cross Compilers: ${pkgs}"
  done
fi

# armhf binaries fail with gcc-4.8, 4.7 has issues on manta.
case ${ARCH} in
  armhf)
    case $SERIES in
      trusty) ADDPKG="${ADDPKG} gcc-4.6" ;;
    esac
    case $SERIES in
      trusty|utopic|vivid|xenial|yakkety|zesty)
        ADDPKG="${ADDPKG} gcc-4.7"
        ;;
    esac
    ;;
  amd64)
    case $SERIES in
      trusty|utopic|vivid|xenial|yakkety|zesty)
        ADDPKG="${ADDPKG} gcc-4.7-arm-linux-gnueabihf"
        ;;
    esac
    ;;
esac

# TEMPORARY: add new Build-Depend:s here before they are in
#            the official archive packages as they are not yet
#            included in the apt-get build-dep instantiation.
#            Or they are needed in a series via a package other
#            than series:linux.
#            XXX: we should use kernel series to instantiate the
#            full list of packages in the series.
case "$SERIES" in
  impish|focal) ADDPKG="${ADDPKG} zstd" ;;
esac
case "$SERIES" in
  hirsute|groovy|focal) ADDPKG="${ADDPKG} dctrl-tools" ;;
esac
case "$SERIES" in
  groovy|focal|bionic) ADDPKG="${ADDPKG} dwarves" ;;
esac
case "$SERIES" in
  eoan|focal) ADDPKG="${ADDPKG} curl" ;;
esac
case "$SERIES" in
  xenial|bionic|cosmic|disco|eoan) ADDPKG="${ADDPKG} default-jdk-headless java-common" ;;
esac
case "$SERIES" in
  xenial|bionic|cosmic|disco) ADDPKG="${ADDPKG} dkms wget curl" ;;
esac
case "$SERIES" in
  xenial) ADDPKG="${ADDPKG} libnuma-dev python-sphinx" ;;
esac
case "$SERIES" in
  xenial|bionic|disco|eoan|focal|groovy|hirsute) ADDPKG="${ADDPKG} libcap-dev" ;;
esac
case "$SERIES" in
  xenial|bionic|focal|groovy|hirsute|impish|jammy) ADDPKG="${ADDPKG} pkg-config" ;;
esac
case "$SERIES" in
  jammy|lunar) ADDPKG="${ADDPKG} rustc-1.62 rust-1.62-src rustfmt-1.62 bindgen-0.56 clang-14 llvm-14" ;;
esac
case "$SERIES" in
  mantic) ADDPKG="${ADDPKG} rustc-1.68 rust-1.68-src rustfmt-1.68 bindgen-0.56 clang-15 llvm-15 libclang1-15" ;;
esac
case "$SERIES" in
  noble)
    ADDPKG="${ADDPKG} rustc-1.73 rust-1.73-src rustfmt-1.73 bindgen-0.65 clang-17 llvm-17 lld-17 libclang1-17"
    # Always include the latest stock Rust toolchain in the latest Ubuntu release
    ADDPKG="${ADDPKG} rustc rust-src rustfmt bindgen clang llvm lld libclang1"
    ;;
esac

# Always needed for selftests, available in all suites, not declared
# as a default build-dep
ADDPKG="${ADDPKG} clang libelf-dev llvm lld libfuse-dev"

dpkg --configure -a
apt-get -y --force-yes update
apt-get -u -y --force-yes dist-upgrade
apt-get -u -y --force-yes autoremove
apt-get clean

apt-get -y --force-yes --no-install-recommends install build-essential
apt-get -y --force-yes build-dep --only-source ${BUILD_DEP}
apt-get -y --force-yes --no-install-recommends install ${ADDPKG}
for pkg in ${ADDPKG}; do
  installed=$(dpkg-query --show --showformat='${Status}' ${pkg} || true)
  if [ "${installed}" != "install ok installed" ]; then
    echo Installing ${pkg}
    apt-get -y --force-yes --no-install-recommends install ${pkg}
  fi
done

# Remove packages which are problematic.
RMPKG=snapcraft
for pkg in ${RMPKG}; do
  installed=$(dpkg-query --show --showformat='${Status}' ${pkg} || true)
  if [ "${installed}" = "install ok installed" ]; then
    echo Removing ${pkg}
    apt-get -y --force-yes remove ${pkg}
  fi
done

# Remove build time http_proxy config
[ ! -e /etc/apt/apt.conf.d/01proxy-from-http_proxy ] || \
    rm /etc/apt/apt.conf.d/01proxy-from-http_proxy

apt-get clean
EOT
