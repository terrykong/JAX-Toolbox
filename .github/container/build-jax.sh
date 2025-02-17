#!/bin/bash

set -e

## Utility methods

print_var() {
    echo "$1: ${!1}"
}

supported_compute_capabilities() {
    ARCH=$1
    if [[ "${ARCH}" == "amd64" ]]; then
        echo "5.2,6.0,6.1,7.0,7.5,8.0,8.6,9.0"
    elif [[ "${ARCH}" == "arm64" ]]; then
        echo "5.3,6.2,7.0,7.2,7.5,8.0,8.6,8.7,9.0"
    else
        echo "Invalid arch '$ARCH' (expected 'amd64' or 'arm64')" 1>&2
        return 1
    fi
}

clean() {
    $(find -type f -executable -iname "bazel*") clean --expunge || true
    rm -rf dist/
    rm -rf bazel
    rm -rf .jax_configure.bazelrc
    rm -rf build WORKSPACE .bazel*
    rm -rf ${HOME}/.cache/bazel
}

## Parse command-line arguments

usage() {
    echo "Configure, build, and install JAX and Jaxlib"
    echo ""
    echo "  Usage: $0 [OPTIONS]"
    echo ""
    echo "    OPTIONS                        DESCRIPTION"
    echo "    --build-param PARAM            Param passed to the jaxlib build command. Can be passed many times."
    echo "    --clean                        Delete local configuration and bazel cache"
    echo "    --clean-only                   Do not build, just cleanup"
    echo "    --cpu-arch                     Target CPU architecture, e.g. amd64, arm64, etc."
    echo "    --debug                        Build in debug mode"
    echo "    --dry                          Dry run, parse arguments only"
    echo "    -h, --help                     Print usage."
    echo "    --jaxlib_only                  Only build and install jaxlib"
    echo "    --no-clean                     Do not delete local configuration and bazel cache (default)"
    echo "    --src-path-jax                 Path to JAX source"
    echo "    --src-path-xla                 Path to XLA source"
    echo "    --sm SM1,SM2,...               Comma-separated list of CUDA SM versions to compile for, e.g. '7.5,8.0'"
    echo "    --sm local                     Query the SM of available GPUs (default)"
    echo "    --sm all                       All current SM"
    echo "                                   If you want to pass a bazel parameter, you must do it like this:"
    echo "                                       --build-param=--bazel_options=..."
    exit $1
}

# Set defaults
BUILD_PARAM=""
CLEAN=0
CLEANONLY=0
CPU_ARCH="$(dpkg --print-architecture)"
CUDA_COMPUTE_CAPABILITIES="local"
DEBUG=0
DRY=0
EDITABLE=0
JAXLIB_ONLY=0
SRC_PATH_JAX="/opt/jax-source"
SRC_PATH_XLA="/opt/xla-source"

args=$(getopt -o h --long build-param:,clean,cpu-arch:,debug,jaxlib_only,no-clean,clean-only,dry,help,src-path-jax:,src-path-xla:,sm: -- "$@")
if [[ $? -ne 0 ]]; then
    exit $1
fi

eval set -- "$args"
while [ : ]; do
    case "$1" in
        --build-param)
            BUILD_PARAM="$BUILD_PARAM $2"
            shift 2
            ;;
        -h | --help)
            usage 1
            ;;
        --clean)
            CLEAN=1
            shift 1
            ;;
        --clean-only)
            CLEANONLY=1
            shift 1
            ;;
        --cpu-arch)
            CPU_ARCH="$2"
            shift 2
            ;;
        --no-clean)
            CLEAN=0
            shift 1
            ;;
        --debug)
            DEBUG=1
            shift 1
            ;;
        --dry)
            DRY=1
            shift 1
            ;;
        --jaxlib_only)
            JAXLIB_ONLY=1
            shift 1
            ;;
        --src-path-jax)
            SRC_PATH_JAX=$2
            shift 2
            ;;
        --src-path-xla)
            SRC_PATH_XLA=$2
            shift 2
            ;;
        --sm)
            CUDA_COMPUTE_CAPABILITIES=$2
            shift 2
            ;;
        --)
            shift;
            break 
            ;;
        *)
            echo "UNKNOWN OPTION $1"
            usage 1
    esac
done

## Set internal variables

SRC_PATH_JAX=$(realpath $SRC_PATH_JAX)
SRC_PATH_XLA=$(realpath $SRC_PATH_XLA)

export DEBIAN_FRONTEND=noninteractive
export TZ=America/Los_Angeles

export TF_NEED_CUDA=1
export TF_NEED_CUTENSOR=1
export TF_NEED_TENSORRT=0
export TF_CUDA_PATHS=/usr,/usr/local/cuda
export TF_CUDNN_PATHS=/usr/lib/$(uname -p)-linux-gnu
export TF_CUDA_VERSION=$(ls /usr/local/cuda/lib64/libcudart.so.*.*.* | cut -d . -f 3-4)
export TF_CUBLAS_VERSION=$(ls /usr/local/cuda/lib64/libcublas.so.*.*.* | cut -d . -f 3)
export TF_CUDNN_VERSION=$(echo "${NV_CUDNN_VERSION}" | cut -d . -f 1)
export TF_NCCL_VERSION=$(echo "${NCCL_VERSION}" | cut -d . -f 1)

case "${CPU_ARCH}" in
    "amd64")
        export CC_OPT_FLAGS="-march=sandybridge -mtune=broadwell"
        ;;
    "arm64")
        export CC_OPT_FLAGS="-march=armv8-a"
        ;;
esac

if [[ ! -z "${CUDA_COMPUTE_CAPABILITIES}" ]]; then
    if [[ "$CUDA_COMPUTE_CAPABILITIES" == "all" ]]; then
        export TF_CUDA_COMPUTE_CAPABILITIES=$(supported_compute_capabilities ${CPU_ARCH})
        if [[ $? -ne 0 ]]; then exit 1; fi
    elif [[ "$CUDA_COMPUTE_CAPABILITIES" == "local" ]]; then
        export TF_CUDA_COMPUTE_CAPABILITIES=$(./local_cuda_arch)
    else
        export TF_CUDA_COMPUTE_CAPABILITIES="${CUDA_COMPUTE_CAPABILITIES}"
    fi
fi

if [[ -d /cache ]]; then
    BUILD_PARAM="${BUILD_PARAM} --bazel_options=--disk_cache=/cache"
fi

if [[ "$DEBUG" == "1" ]]; then
    BUILD_PARAM="${BUILD_PARAM} --bazel_options=-c --bazel_options=dbg --bazel_options=--strip=never --bazel_options=--cxxopt=-g --bazel_options=--cxxopt=-O0"
fi

## Print info

echo "=================================================="
echo "                  Configuration                   "
echo "--------------------------------------------------"

print_var CLEAN
print_var CLEANONLY
print_var CPU_ARCH
print_var CUDA_COMPUTE_CAPABILITIES
print_var DEBUG
print_var BUILD_PARAM
print_var SRC_PATH_JAX
print_var SRC_PATH_XLA

print_var TF_CUDA_VERSION
print_var TF_CUDA_COMPUTE_CAPABILITIES
print_var TF_CUBLAS_VERSION
print_var TF_CUDNN_VERSION
print_var TF_NCCL_VERSION
print_var CC_OPT_FLAGS

print_var BUILD_PARAM

echo "=================================================="

if [[ ${DRY} == 1 ]]; then
    echo "Dry run, exiting..."
    exit 0
fi

if [[ ${CLEANONLY} == 1 ]]; then
    clean
    exit 0
fi

set -x

## install tools

apt-get update
apt-get upgrade -y
apt-get install -y \
    build-essential \
    checkinstall \
    clang \
    git \
    lld \
    wget \
    curl

pip install wheel pre-commit mypy numpy

## Build jaxlib

pushd $SRC_PATH_JAX

time CC=clang CXX=clang++ python build/build.py \
    --enable_cuda \
    --cuda_path=$TF_CUDA_PATHS \
    --cudnn_path=$TF_CUDNN_PATHS \
    --cuda_version=$TF_CUDA_VERSION \
    --cudnn_version=$TF_CUDNN_VERSION \
    --cuda_compute_capabilities=$TF_CUDA_COMPUTE_CAPABILITIES \
    --enable_nccl=true \
    --bazel_options=--linkopt=-fuse-ld=lld \
    --bazel_options=--override_repository=xla=$SRC_PATH_XLA \
    $BUILD_PARAM

popd

## Install the built packages

pushd $SRC_PATH_JAX

# Uninstall jaxlib in case this script was used before.
if [[ "$JAXLIB_ONLY" == "0" ]]; then
    pip uninstall -y jax jaxlib
else
    pip uninstall -y jaxlib
fi

# install jaxlib
pip --disable-pip-version-check install dist/*.whl

# install jax
if [[ "$JAXLIB_ONLY" == "0" ]]; then
    pip --disable-pip-version-check install .
fi

popd

## Cleanup

pushd $SRC_PATH_JAX

if [[ "$CLEAN" == "1" ]]; then
    clean
fi

popd
