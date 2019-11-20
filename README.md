# xtensa-toolchain
A Bash script to generate toolchain package (deb) for SOF development

The script follows the instructions on the SOF website to build the toolchain including
xtensa cross compilers and header files. The size of toolchain for each DSP platform
is around 200+ MB so the total install size could be as large as around 1.2 GB!

Before running the script, you need to install the bison and flex package or the
build process will fail.

$ sudo apt-get install bison flex

If nothing goes wrong, you can find the xtensa-toolchain_<year>.<date>-1.deb in
the same directory running the script. The package will install the toolchain under
target machine's /opt/xtensa-toolchain directory, so you need to add following
pathes manually in your ~/.bashrc file.

export PATH=/opt/xtensa-toolchain/xtensa-byt-elf/bin/:$PATH
export PATH=/opt/xtensa-toolchain/xtensa-hsw-elf/bin/:$PATH
export PATH=/opt/xtensa-toolchain/xtensa-apl-elf/bin/:$PATH
export PATH=/opt/xtensa-toolchain/xtensa-cnl-elf/bin/:$PATH
export PATH=/opt/xtensa-toolchain/xtensa-imx-elf/bin/:$PATH

It assumes the SOF source and the xtensa-root directory are siblings. You can create
a softlink to satisfy the requirement.

$ ln -sf /opt/xtensa-toolchain/xtensa-root xtensa-root


Please refer to following SOF webpage for more detail.
https://thesofproject.github.io/latest/getting_started/build-guide/build-from-scratch.html

