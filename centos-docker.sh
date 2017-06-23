#!/bin/bash
#
# docker.sh
#
# Create, run, and test CentOS 7 ppc64le docker image.

set -x
set -e

GIT_REPOS=( \
"https://github.com/CentOS/sig-cloud-instance-build" \
"https://github.com/CentOS/sig-core-t_docker"
)

WORKDIR=$(pwd)/build

function prepare {
    mkdir ${WORKDIR}

    yum -y install git wget

    pushd ${WORKDIR}
    for repo in "${GIT_REPOS[@]}"
    do
        git clone ${repo}
    done
    popd

    patch -N /usr/sbin/livemedia-creator \
	  0001-Add-ppc64le-kernel-path.patch | :

    patch -N /usr/share/virt-manager/virtinst/urlfetcher.py \
	  0001-Update-initrd-and-kernel-path-for-ppc64le-platform.patch | :

    pushd ${WORKDIR}/sig-cloud-instance-build/docker
    git fetch origin pull/65/head:pr65
    git rebase origin/master
    git merge --no-commit pr65

    # alter x86 kickstart file with ppc64le modifications
    cp centos-7.ks centos-7ppc64le.ks

    sed -i 's!mirrors.kernel.org!mirror.centos.org!' centos-7ppc64le.ks
    sed -i 's!centos/7!altarch/7!' centos-7ppc64le.ks
    sed -i 's!x86_64!ppc64le!' centos-7ppc64le.ks
    sed -i '\!part / *!a\part prepboot --fstype "PPC PReP Boot" --size=10' centos-7ppc64le.ks

    # increase guest memory to avoid possible kernel errors with low memory
    sed -i 's/\(time livemedia.*\)/\1 --ram 4096/' containerbuild.sh
    popd

    pushd ${WORKDIR}/sig-core-t_docker
    git fetch origin pull/2/head:pr2
    git checkout pr2
    git rebase origin/master
    # do not fetch the image from dockerhub
    chmod -x tests/p_docker/10_docker_get_centos_img.sh
    popd

    yum -y install qemu-kvm-ev qemu-kvm-common-ev qemu-kvm-tools-ev \
        qemu-img-ev libvirt
    yum -y install docker
}


function run {
    setenforce 0

    systemctl start libvirtd

    pushd ${WORKDIR}/sig-cloud-instance-build/docker
    ./containerbuild.sh centos-7ppc64le.ks || { echo "Build failed"; exit 1; }
    popd

    systemctl start docker
    cat /var/tmp/containers/$(date +%Y%m%d)/centos-7ppc64le/docker/centos-7ppc64le-docker.tar.xz | docker import - centos:latest
    docker tag centos:latest centos:centos7

    pushd ${WORKDIR}/sig-core-t_docker
    ./runtests.sh
    popd
}

[ ! -d "${WORKDIR}" ] && prepare
run

exit 0
