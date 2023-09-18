FROM ubuntu:23.10

LABEL org.opencontainers.image.authors="johannes.dieterich@amd.com"

ENV TZ=America/Chicago
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

# to allow for build-dep
RUN sed -Ei 's/^# deb-src /deb-src /' /etc/apt/sources.list
RUN apt update
RUN apt upgrade -y
# generic things
RUN apt install -y sudo wget gnupg2 git gcc bzip2 cmake build-essential numactl vim llvm-15-dev clang-15 libclang-15-dev xxd lld-15 clang-tools-15 libunwind-15-dev libclc-15 clinfo
# Mesa build-deps
RUN apt-get build-dep -y mesa
# rusticl build deps
RUN apt install -y rustc meson bindgen

# get SPIRV tools
WORKDIR /root
RUN wget https://github.com/KhronosGroup/SPIRV-Tools/archive/refs/tags/v2022.3.tar.gz
RUN tar xzf v2022.3.tar.gz
WORKDIR SPIRV-Tools-2022.3
RUN python3 utils/git-sync-deps
WORKDIR mkdir build
RUN cmake -G Ninja -DCMAKE_CXX_COMPILER=clang++-15 -DCMAKE_CXX_STANDARD=20 -DCMAKE_BUILD_TYPE=Release -DCMAKE_CXX_FLAGS="-Wno-deprecated-anon-enum-enum-conversion" ..
RUN ninja install

# SPIRV LLVM translator
WORKDIR /root
RUN wget https://github.com/KhronosGroup/SPIRV-LLVM-Translator/archive/refs/tags/v15.0.0.tar.gz
RUN tar xzf v15.0.0.tar.gz
WORKDIR SPIRV-LLVM-Translator-15.0.0
RUN mkdir build
WORKDIR build
RUN cmake -G Ninja -DCMAKE_CXX_COMPILER=clang++-15 -DCMAKE_BUILD_TYPE=Release ..
RUN ninja install

# build mesa with rusticl
WORKDIR /root
RUN git clone https://gitlab.freedesktop.org/mesa/mesa.git # https://gitlab.freedesktop.org/karolherbst/mesa.git
WORKDIR mesa
RUN git checkout main
RUN meson setup builddir/ -Dgallium-rusticl=true -Dllvm=enabled -Drust_std=2021
RUN ninja -C builddir/
RUN ninja -C builddir/ install

#setup the rusticl ICD
RUN mkdir -p /etc/OpenCL/vendors
RUN echo libRusticlOpenCL.so > /etc/OpenCL/vendors/rusticl.icd
RUN echo /usr/local/lib/x86_64-linux-gnu/ > /etc/ld.so.conf.d/rusticl.conf
RUN ldconfig

# enable radeonsi for rusticl
RUN echo "export RUSTICL_ENABLE=radeonsi" >> /root/.bashrc
RUN echo "export RUSTICL_FEATURES=fp64" >> /root/.bashrc

# get tornado
WORKDIR /root
RUN apt install -y openjdk-17-jdk-headless maven opencl-clhpp-headers opencl-c-headers python3-pip python3-wget ocl-icd-opencl-dev
RUN git clone https://github.com/beehive-lab/TornadoVM.git
WORKDIR TornadoVM
RUN git checkout develop
RUN ./scripts/tornadovm-installer --jdk jdk17 --backend opencl
#RUN ./scripts/tornadovm-installer --jdk jdk17 --backend spirv,opencl

RUN echo "source /root/TornadoVM/setvars.sh" >> /root/.bashrc
