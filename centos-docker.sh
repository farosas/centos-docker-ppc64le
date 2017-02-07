#!/bin/bash
#
# docker.sh
#
# Create, run, and test CentOS 7 ppc64le docker image.

set -x
set -e

GIT_REPOS=( \
"https://github.com/CentOS/sig-cloud-instance-build" \
"https://github.com/CentOS/sig-core-t_docker" \
"https://github.com/virt-manager/virt-manager virt-manager-src" \
"https://github.com/rhinstaller/lorax lorax-src" \
"https://git.centos.org/git/rpms/virt-manager" \
"https://git.centos.org/git/rpms/lorax" \
"https://git.centos.org/git/centos-git-common" \
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

    pushd ${WORKDIR}/lorax-src
    ln -fs ${WORKDIR}/centos-git-common/*.sh /usr/local/bin/

    git config user.email root@localhost
    git config user.name root
    git fetch origin pull/149/head:pr149
    git checkout pr149
    git format-patch -1
    popd

    pushd ${WORKDIR}/virt-manager-src
    git config user.email root@localhost
    git config user.name root
    git checkout v1.4.0
    git cherry-pick cd35470e3c55aa64976cd0a96a6cfd756f71de17
    git format-patch -1
    popd
}

function build {
    yum -y install yum-utils rpm-build

    for pkg in lorax virt-manager
    do
        pushd ${WORKDIR}/${pkg}
        specfile=SPECS/${pkg}.spec
        git checkout c7
        get_sources.sh
        patch=../${pkg}-src/0001*
        cp ${patch} SOURCES
        sed -i "/%description$/iPatch99: $(basename $patch)" ${specfile}
        sed -i '/%build/i%patch99 -p1' ${specfile}
        into_srpm.sh
        yum-builddep -y ${specfile}
        rpmbuild --nodeps --define "%_topdir `pwd`" -bs ${specfile} && \
        rpmbuild --define "%_topdir `pwd`" -ba ${specfile}
        popd
    done

    pushd ${WORKDIR}/sig-cloud-instance-build
    git config user.email root@localhost
    git config user.name root
    git fetch origin pull/85/head:pr85
    git fetch origin pull/65/head:pr65
    git checkout pr85
    git rebase origin/master
    git merge --no-commit pr65
    popd

    pushd ${WORKDIR}/sig-core-t_docker
    git config user.email root@localhost
    git config user.name root
    git fetch origin pull/2/head:pr2
    git checkout pr2
    git rebase origin/master
    # do not fetch the image from dockerhub
    chmod -x tests/p_docker/10_docker_get_centos_img.sh
    popd

    yum -y localinstall lorax/RPMS/ppc64le/*
    yum -y localinstall virt-manager/RPMS/noarch/*
    yum -y install qemu-kvm-ev qemu-kvm-common-ev qemu-kvm-tools-ev \
        qemu-img-ev libvirt
    yum -y install docker
}


function run {
    # there is an issue when running docker with selinux in enforcing
    # mode
    setenforce 0

    systemctl start libvirtd

    pushd ${WORKDIR}/sig-cloud-instance-build/docker
    # increase guest memory to avoid possible kernel errors with low memory
    sed -i 's/\(time livemedia.*\)/\1 --ram 4096/' containerbuild.sh
    ./containerbuild.sh centos-7ppc64le.ks || { echo "Build failed"; exit 1; }
    popd

    systemctl start docker
    cat /var/tmp/containers/$(date +%Y%m%d)/centos-7ppc64le/docker/centos-7ppc64le-docker.tar.xz | docker import - centos:latest
    docker tag centos:latest centos:centos7

    pushd ${WORKDIR}/sig-core-t_docker
    ./runtests.sh
    popd
}

if [ ! -d "${WORKDIR}" ]
then
    prepare
    build
fi
run

exit 0
