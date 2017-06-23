#!/bin/bash
#
# docker.sh
#
# Create, run, and test CentOS 7 ppc64le docker image.

set -x
set -e

WORK_DIR=$(pwd)/build
CONTAINERS_DIR=/var/tmp/containers
TODAY=$(date +%Y%m%d)

function install_deps {
    yum -y install qemu-kvm-ev qemu-kvm-common-ev qemu-kvm-tools-ev \
        qemu-img-ev libvirt
    yum -y install lorax virt-install
    yum -y install docker
}

function prepare {
    install_deps

    patch -N /usr/sbin/livemedia-creator \
	  0001-Add-ppc64le-kernel-path.patch || :

    patch -N /usr/share/virt-manager/virtinst/urlfetcher.py \
	  0001-Update-initrd-and-kernel-path-for-ppc64le-platform.patch || :

    mkdir ${WORK_DIR}
    pushd ${WORK_DIR}

    git clone https://github.com/CentOS/sig-cloud-instance-build
    git clone https://github.com/CentOS/sig-core-t_docker

    pushd sig-cloud-instance-build/docker
    git fetch origin pull/65/head:pr65
    git rebase origin/master
    git merge --no-commit pr65

    # alter x86 kickstart file with ppc64le modifications
    cp centos-7.ks centos-7ppc64le.ks

    sed -i 's!mirrors.kernel.org!mcentos.org!' centos-7ppc64le.ks
    sed -i 's!centos/7!altarch/7!' centos-7ppc64le.ks
    sed -i 's!x86_64!ppc64le!' centos-7ppc64le.ks
    sed -i '\!part / *!a\part prepboot --fstype "PPC PReP Boot" --size=10' centos-7ppc64le.ks

    # increase guest memory to avoid possible kernel errors with low memory
    sed -i 's/\(time livemedia.*\)/\1 --ram 4096/' containerbuild.sh

    popd
    popd
}

function build_tarball {
    systemctl start libvirtd

    pushd ${WORK_DIR}/sig-cloud-instance-build/docker
    ./containerbuild.sh centos-7ppc64le.ks
    popd

    mv ${CONTAINERS_DIR}/${TODAY}/centos-7ppc64le/docker/centos-7ppc64le-docker.tar.xz .
}

function create_docker_img {
    systemctl start docker

    cat centos-7ppc64le-docker.tar.xz | docker import - centos:latest
    docker tag centos:latest centos:centos${TODAY}
    docker tag centos:latest centos:centos7
    docker tag centos:latest centos:7
}

function test_docker_img {
    pushd ${WORK_DIR}/sig-core-t_docker
    git fetch origin pull/2/head:pr2
    git checkout pr2
    git rebase origin/master
    # do not fetch the image from dockerhub
    chmod -x tests/p_docker/10_docker_get_centos_img.sh

    ./runtests.sh
    popd
}

function run {
    build_tarball
    create_docker_img
    test_docker_img
}

function clean {
    [ -d "${WORK_DIR}" ] && rm -rf ${WORK_DIR}
    [ -d "${CONTAINERS_DIR}" ] && rm -rf ${CONTAINERS_DIR}
}

[ ! -d "${WORK_DIR}" ] && prepare
run || clean

exit 0
