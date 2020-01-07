#!/bin/bash

clean_up() {
	if [ ${#} -ne 0 ]
	then
		echo -e "${FUNCNAME[0]}: incorrect parameter number ${#}"
		return 1
	fi

	if [ -e "xtensa-overlay" ]
	then
		echo -p "remove old xtensa-overlay folder"
		rm -rf xtensa-overlay
	fi

	if [ -e "crosstool-ng" ]
	then
		echo -p "remove old crosstool-ng folder"
		rm -rf crosstool-ng
	fi

	if [ -e "newlib-xtensa" ]
	then
		echo -p "remove old newlib-xtensa folder"
		rm -rf newlib-xtensa
	fi

	return 0
}

clone_repositories() {
	if [ ${#} -ne 0 ]
	then
		echo -e "${FUNCNAME[0]}: incorrect parameter number ${#}"
		return 1
	fi

	# Clone both repos and check out the sof-gcc8.1 branch.
	git clone https://github.com/thesofproject/xtensa-overlay.git
	cd ${ROOT_DIR}/xtensa-overlay
	git checkout sof-gcc8.1
	GITHASH_XTENSA=$(git log --format=%H -n 1)
	echo "GITHASH_XTENSA=${GITHASH_XTENSA}"

	cd ${ROOT_DIR}
	git clone https://github.com/thesofproject/crosstool-ng.git
	cd ${ROOT_DIR}/crosstool-ng
	git checkout sof-gcc8.1
	GITHASH_CROSSTOOL=$(git log --format=%H -n 1)
	echo "GITHASH_CROSSTOOL=${GITHASH_CROSSTOOL}"

	# Clone the header repository.
	cd ${ROOT_DIR}
	git clone https://github.com/jcmvbkbc/newlib-xtensa.git
	cd ${ROOT_DIR}/newlib-xtensa
	git checkout -b xtensa origin/xtensa
	GITHASH_NEWLIB=$(git log --format=%H -n 1)
	echo "GITHASH_NEWLIB=${GITHASH_NEWLIB}"

	return 0
}

build_toolchain() {
	if [ ${#} -ne 0 ]
	then
		echo -e "${FUNCNAME[0]}: incorrect parameter number ${#}"
		return 1
	fi

	# Build and install the ct-ng tools in the local folder.
	cd ${ROOT_DIR}/crosstool-ng
	./bootstrap
	./configure --prefix=`pwd`
	make
	make install

	CONFIG=("config-byt-gcc8.1-gdb8.1" "config-hsw-gcc8.1-gdb8.1" "config-apl-gcc8.1-gdb8.1" "config-cnl-gcc8.1-gdb8.1" "config-imx-gcc8.1-gdb8.1")
	TARGET=("xtensa-byt-elf" "xtensa-hsw-elf" "xtensa-apl-elf" "xtensa-cnl-elf" "xtensa-imx-elf")

	# Copy the config files to .config and build the cross compiler for your target platforms.
	for ((idx=0; idx<${#CONFIG[@]}; ++idx)); do
		cp ${CONFIG[idx]} .config
		./ct-ng build
		export PATH=${ROOT_DIR}/crosstool-ng/builds/${TARGET[idx]}/bin/:${PATH}
	done

	# Build and install the headers for each platform.
	cd ${ROOT_DIR}/newlib-xtensa
	for ((idx=0; idx<${#TARGET[@]}; ++idx)); do
		./configure --target=${TARGET[idx]} --prefix=${ROOT_DIR}/crosstool-ng/builds/xtensa-root
		make
		make install
		rm -fr rm etc/config.cache
	done

	return 0
}

make_deb_package() {
	if [ ${#} -ne 0 ]
	then
		echo -e "${FUNCNAME[0]}: incorrect parameter number ${#}"
		return 1
	fi

	MAJOR_VERSION=$(date +%Y)
	MINOR_VERSION=$(date +%m%d)
	PACKAGE_REVISION="1"
	PACKAGE_NAME="xtensa-toolchain"
	PACKAGE_ROOT="${PACKAGE_NAME}_${MAJOR_VERSION}.${MINOR_VERSION}-${PACKAGE_REVISION}"

	# Make a simple package for it
	cd ${ROOT_DIR}
	mkdir -p ${PACKAGE_ROOT}/opt
	mkdir -p ${PACKAGE_ROOT}/DEBIAN
	mv ${ROOT_DIR}/crosstool-ng/builds ${PACKAGE_ROOT}/opt/${PACKAGE_NAME}
	cat >> ${PACKAGE_ROOT}/DEBIAN/control << EOF
	Package: ${PACKAGE_NAME}
	Version: ${MAJOR_VERSION}.${MINOR_VERSION}-${PACKAGE_REVISION}
	Section: devel
	Priority: optional
	Architecture: amd64
	Depends:
	Maintainer: Brent Lu <brent.lu@intel.com>
	Description: Toolchain for SOF firmware
	 Git commits:
	   crosstool-ng:   ${GITHASH_CROSSTOOL}
	   xtensa-overlay: ${GITHASH_XTENSA}
	   newlib-xtensa:  ${GITHASH_NEWLIB}
EOF

	dpkg-deb --build ${PACKAGE_ROOT}}

	return 0
}

main() {

	ROOT_DIR=$(pwd)
	local download_only=0

	while getopts d option
	do
		case "${option}" in
		"d")
			download_only=1
			;;
		*)
			echo -e "ERROR: Unknown option '${OPTARG}'"
			;;
		esac
	done

	clean_up
	if [ $? -ne 0 ]
	then
		echo -e "${FUNCNAME[0]}: clean_up fail"
		return 1
	fi

	clone_repositories
	if [ $? -ne 0 ]
	then
		echo -e "${FUNCNAME[0]}: clone_repositories fail"
		return 1
	fi

	if [ ${download_only} -ne 0 ]
	then
		echo -e "download repositories only"
		return 0
	fi

	build_toolchain
	if [ $? -ne 0 ]
	then
		echo -e "${FUNCNAME[0]}: build_toolchain fail"
		return 1
	fi

	make_deb_package
	if [ $? -ne 0 ]
	then
		echo -e "${FUNCNAME[0]}: make_deb_package fail"
		return 1
	fi

	return 0
}

# call main funcion
main "$@"
if [ $? -ne 0 ]
then
	echo -e "\nScript Fail"
	exit 1
fi

echo -e "\nScript Success"
