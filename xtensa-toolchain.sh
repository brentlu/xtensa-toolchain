#!/bin/bash

clean_up() {
	local root_dir=${1}

	if [ ${#} -ne 1 ]
	then
		echo -e "${FUNCNAME[0]}: incorrect parameter number ${#}"
		return 1
	fi

	cd ${root_dir}

	echo -e "Cleaning up old repositories..."

	if [ -e "xtensa-overlay" ]
	then
		echo -e "  remove old xtensa-overlay folder"
		rm -rf xtensa-overlay
	fi

	if [ -e "crosstool-ng" ]
	then
		echo -e "  remove old crosstool-ng folder"
		rm -rf crosstool-ng
	fi

	if [ -e "newlib-xtensa" ]
	then
		echo -e "  remove old newlib-xtensa folder"
		rm -rf newlib-xtensa
	fi

	return 0
}

clone_repositories() {
	local root_dir=${1}

	if [ ${#} -ne 1 ]
	then
		echo -e "${FUNCNAME[0]}: incorrect parameter number ${#}"
		return 1
	fi

	echo -e "Cloning new repositories..."

	# Clone both repos and check out the sof-gcc8.1 branch.
	cd ${root_dir}
	git clone https://github.com/thesofproject/xtensa-overlay.git
	cd ${root_dir}/xtensa-overlay
	git checkout sof-gcc8.1
	GITHASH_XTENSA=$(git log --format=%H -n 1)

	cd ${root_dir}
	git clone https://github.com/thesofproject/crosstool-ng.git
	cd ${root_dir}/crosstool-ng
	git checkout sof-gcc8.1
	GITHASH_CROSSTOOL=$(git log --format=%H -n 1)

	# Clone the header repository.
	cd ${root_dir}
	git clone https://github.com/jcmvbkbc/newlib-xtensa.git
	cd ${root_dir}/newlib-xtensa
	git checkout -b xtensa origin/xtensa
	GITHASH_NEWLIB=$(git log --format=%H -n 1)

	echo -e "Cloning success:"
	echo -e "GITHASH_XTENSA     = ${GITHASH_XTENSA}"
	echo -e "GITHASH_CROSSTOOL  = ${GITHASH_CROSSTOOL}"
	echo -e "GITHASH_NEWLIB     = ${GITHASH_NEWLIB}\n"

	return 0
}

build_toolchain() {
	local root_dir=${1}

	if [ ${#} -ne 1 ]
	then
		echo -e "${FUNCNAME[0]}: incorrect parameter number ${#}"
		return 1
	fi

	echo -e "Building toolchain..."

	# Build and install the ct-ng tools in the local folder.
	cd ${root_dir}/crosstool-ng
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
		export PATH=${root_dir}/crosstool-ng/builds/${TARGET[idx]}/bin/:${PATH}
	done

	# Build and install the headers for each platform.
	cd ${root_dir}/newlib-xtensa
	for ((idx=0; idx<${#TARGET[@]}; ++idx)); do
		./configure --target=${TARGET[idx]} --prefix=${root_dir}/crosstool-ng/builds/xtensa-root
		make
		make install
		rm -fr rm etc/config.cache
	done

	return 0
}

make_deb_package() {
	local root_dir=${1}

	if [ ${#} -ne 1 ]
	then
		echo -e "${FUNCNAME[0]}: incorrect parameter number ${#}"
		return 1
	fi

	echo -e "Making deb package..."

	MAJOR_VERSION=$(date +%Y)
	MINOR_VERSION=$(date +%m%d)
	PACKAGE_REVISION="1"
	PACKAGE_NAME="xtensa-toolchain"
	PACKAGE_ROOT="${PACKAGE_NAME}_${MAJOR_VERSION}.${MINOR_VERSION}-${PACKAGE_REVISION}"

	# Make a simple package for it
	cd ${root_dir}
	mkdir -p ${PACKAGE_ROOT}/opt
	mkdir -p ${PACKAGE_ROOT}/DEBIAN
	mv ${root_dir}/crosstool-ng/builds ${PACKAGE_ROOT}/opt/${PACKAGE_NAME}
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

	dpkg-deb --build ${PACKAGE_ROOT}

	return 0
}

read_deb_file() {
	local root_dir=${1}
	local deb_file=${2}

	if [ ${#} -ne 2 ]
	then
		echo -e "${FUNCNAME[0]}: incorrect parameter number ${#}"
		return 1
	fi

	local info

	cd ${root_dir}

	echo -e "Reading deb file..."

	info=$(dpkg --info ${deb_file})

	while IFS= read -r line
	do
		if [[ "${line}" == *"crosstool-ng:"* ]]
		then
			DEB_FILE_CROSSTOOL=${line##*:}
			DEB_FILE_CROSSTOOL=${DEB_FILE_CROSSTOOL##*[[:blank:]]}
		fi

		if [[ "${line}" == *"xtensa-overlay:"* ]]
		then
			DEB_FILE_XTENSA=${line##*:}
			DEB_FILE_XTENSA=${DEB_FILE_XTENSA##*[[:blank:]]}
		fi

		if [[ "${line}" == *"newlib-xtensa:"* ]]
		then
			DEB_FILE_NEWLIB=${line##*:}
			DEB_FILE_NEWLIB=${DEB_FILE_NEWLIB##*[[:blank:]]}
		fi
	done <<< "${info}"

	echo -e "Reading success:"
	echo -e "DEB_FILE_XTENSA    = ${DEB_FILE_XTENSA}"
	echo -e "DEB_FILE_CROSSTOOL = ${DEB_FILE_CROSSTOOL}"
	echo -e "DEB_FILE_NEWLIB    = ${DEB_FILE_NEWLIB}\n"

	return 0
}

main() {
	local action=${1}

	if [ ${#} -eq 0 ]
	then
		echo -e "ERROR: No action specified"
		show_usage
		if [ $? -ne 0 ]
		then
			echo -e "${FUNCNAME[0]}: show_usage fail"
			return 1
		fi

		return 1
	fi

	local root_dir=$(pwd)
	local deb_file=""

	echo -e "Action '${action}'"

	shift

	while getopts p: option
	do
		case "${option}" in
		"p")
			echo -e "Option found, deb file: '${OPTARG}'"
			deb_file="${OPTARG}"
			;;
		*)
			echo -e "ERROR: Unknown option '${OPTARG}'"
			;;
		esac
	done

	case "${action}" in
	"check")
		if [[ -z "${deb_file}" ]]
		then
			echo -e "ERROR: No deb file specified"
			return 1
		fi

		if [ ! -e ${deb_file} ]
		then
			echo -e "ERROR: deb file not exist"
			return 1
		fi

		clean_up "${root_dir}"
		if [ $? -ne 0 ]
		then
			echo -e "${FUNCNAME[0]}: clean_up fail"
			return 1
		fi

		clone_repositories "${root_dir}"
		if [ $? -ne 0 ]
		then
			echo -e "${FUNCNAME[0]}: clone_repositories fail"
			return 1
		fi

		read_deb_file "${root_dir}" "${deb_file}"
		if [ $? -ne 0 ]
		then
			echo -e "${FUNCNAME[0]}: read_deb_file fail"
			return 1
		fi

		if [[ "${DEB_FILE_CROSSTOOL}" == "${GITHASH_CROSSTOOL}" ]] &&
		   [[ "${DEB_FILE_XTENSA}" == "${GITHASH_XTENSA}" ]] &&
		   [[ "${DEB_FILE_NEWLIB}" == "${GITHASH_NEWLIB}" ]]
		then
			echo -e "The toolchain is up-to-date\n"
		else
			echo -e "The toolchain in out-of-date\n"
		fi

		# clean up again
		clean_up "${root_dir}"
		if [ $? -ne 0 ]
		then
			echo -e "${FUNCNAME[0]}: clean_up fail"
			return 1
		fi
		;;

	"download")
		clean_up "${root_dir}"
		if [ $? -ne 0 ]
		then
			echo -e "${FUNCNAME[0]}: clean_up fail"
			return 1
		fi

		clone_repositories "${root_dir}"
		if [ $? -ne 0 ]
		then
			echo -e "${FUNCNAME[0]}: clone_repositories fail"
			return 1
		fi
		;;
		
	"build")
		clean_up "${root_dir}"
		if [ $? -ne 0 ]
		then
			echo -e "${FUNCNAME[0]}: clean_up fail"
			return 1
		fi

		clone_repositories "${root_dir}"
		if [ $? -ne 0 ]
		then
			echo -e "${FUNCNAME[0]}: clone_repositories fail"
			return 1
		fi

		build_toolchain "${root_dir}"
		if [ $? -ne 0 ]
		then
			echo -e "${FUNCNAME[0]}: build_toolchain fail"
			return 1
		fi

		make_deb_package "${root_dir}"
		if [ $? -ne 0 ]
		then
			echo -e "${FUNCNAME[0]}: make_deb_package fail"
			return 1
		fi
		;;
	*)
		echo -e "ERROR: Unknown action '${action}', should be 'check', 'download' or 'build'"
		;;
	esac

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
