
# Nard Linux SDK
# http://www.arbetsmyra.dyndns.org/nard
# Copyright (C) 2014-2017 Ronny Nilsson



#-----------------------------
# Get topdir regardles of where we start by searching
# upwards in hierarchy to this file. (Thus, it searches
# for itself).
ifndef PATH_TOP
	export PATH_TOP := $(strip $(shell						   \
		until test -f ./Rules.mk							&& \
				grep -q "theredfoxjumpedhigh" ./Rules.mk	|| \
				test "$$PWD" = "/"; do					       \
			cd ..											 ; \
		done												&& \
		pwd))
endif

# Define basic variables
# common for all targets
export PATH_INTER := $(PATH_TOP)/intermediate
export PATH_SCRAP := $(PATH_INTER)/scrap
export PATH_FS := $(PATH_INTER)/fs
export PATH_BOOT := $(PATH_INTER)/boot
export PATH_UTIL := $(PATH_TOP)/util
export PATH_IMAGES := $(PATH_TOP)/images
export PATH_APPS := $(PATH_TOP)/apps
export PATH_LINUX := $(PATH_APPS)/linux-kernel/linux-kernel
export PATH_PRODUCT = $(PATH_TOP)/platform/$(strip $(PRODUCT))
export PATH_BOARD = $(PATH_TOP)/platform/$(strip $(BOARD))
export PATH := $(PATH):/sbin:/usr/sbin:/usr/local/sbin:$(PATH_UTIL)/bin

export LANG := C
export LC_ALL := C
export SHELL := /bin/bash
export PERL := perl
export CP := cp
export SSH_KEYGEN := ssh-keygen
export MAKE

ifndef CPUS
	# Run compiler with low prio and use all available processors
	export CPUS := $(shell														\
		for A in _NPROCESSORS_ONLN _SC_NPROCESSORS_ONLN							\
				_NPROCESSORS_CONF _SC_NPROCESSORS_CONF; do						\
			getconf $$A 2>/dev/null && exit 0;									\
		done || echo -n "1")

	dummy := $(shell chrt -p -b 0 $$PPID >/dev/null 2>&1)
	dummy := $(shell renice 15 -g $$PPID >/dev/null 2>&1)
	dummy := $(shell ionice -c 2 -n 6 -p $$PPID >/dev/null 2>&1)
endif


#-----------------------------
# Lib functions for extracting name, version, branch, tag
# config files, URL etc. of the "current" application to build
# from product Rules.
PKG_NAME := $(notdir $(CURDIR))
pkg_top = $(firstword															\
		$(filter $(PKG_NAME)/%, $(PKGS_APPS) $(PKGS_UTILS))						\
	)
PKG_VER = $(firstword															\
		$(if $(findstring .tar.,$(pkg_top)),									\
			$(PKG_NAME)-$(notdir												\
				$(subst -,/,													\
					$(basename													\
						$(basename $(pkg_top))									\
					)															\
				)																\
			)																	\
		)																		\
		$(notdir																\
			$(filter $(PKG_NAME)/$(PKG_NAME)-%, $(pkg_top))						\
		)																		\
		$(if $(pkg_branch),														\
			$(PKG_NAME)-$(pkg_branch)											\
		)																		\
		$(PKG_NAME)																\
		$(if $(pkg_top),,														\
			$(error Error; $(PKG_NAME) is missing in in the product recipe)		\
		)																		\
	)
PKG_CONF = $(or																	\
		$(strip																	\
			$(foreach dep,														\
				$(call reverse,													\
					$(PRODUCT_DEPS) $(BOARD_DEPS)								\
				),																\
				$(wildcard $(PATH_TOP)/platform/$(dep)/$(PKG_VER).config)		\
			)																	\
		),																		\
		$(firstword																\
			$(call reverse,														\
				$(sort															\
					$(foreach dep,												\
						$(PRODUCT_DEPS) $(BOARD_DEPS),							\
						$(wildcard												\
							$(PATH_TOP)/platform/$(dep)/$(PKG_NAME)-*.config	\
						)														\
					)															\
				)																\
			)																	\
		),																		\
		$(PKG_VER).config														\
	)
# Application package Uniform Resource Name. Format examples (note the
# missing colon character in http:// etc though)
#   - myapp/myapp-2.0                                 (local tarball myapp-2.0.tar.gz)
#   - myapp/http//example.com/myapp.tar.gz            (remote tarball)
#   - myapp/http//example.com/myapp-2.0.tar.gz        (remote tarball)
#       patchlist exmple: myapp-2.0.patchlist         (remote tarball)
#   - myapp/ftp//example.com/myapp.tar.bz2
#   - myapp/http//example.com/proj/myapp.git          (RO GIT, master branch)
#       patchlist exmple: myapp-master.patchlist
#   - myapp/git//example.com/proj/myapp.git           (RO GIT, master branch)
#       patchlist exmple: myapp-master.patchlist
#   - myapp/http//example.com/proj/myapp.git^branch   (RO GIT, specific branch, tag or commit hash)
#       patchlist example: myapp-branch.patchlist
#   - myapp/user@example.com/proj/myapp.git^branch    (RW GIT, specific branch, tag or commit hash)
pkg_urn = $(strip 																\
		$(subst //,://,															\
			$(subst ^$(PKG_NAME)/,,^$(pkg_top))									\
		)																		\
	)
# Application package Uniform Resource Locator. Basically it's
# the package URN with optional GIT branch striped.
pkg_url = $(firstword															\
		$(if $(findstring .tar.,$(pkg_urn)),									\
			$(pkg_urn)															\
		)																		\
		$(if $(findstring .git,$(pkg_urn)),										\
			$(firstword															\
				$(subst ^, ,$(pkg_urn))											\
			)																	\
		)																		\
		$(if $(wildcard $(pkg_urn).tar.bz2),									\
			$(pkg_urn).tar.bz2													\
		)																		\
		$(if $(wildcard $(pkg_urn).tar.gz),										\
			$(pkg_urn).tar.gz													\
		)																		\
	)
# Extract optional GIT branch from package URN.
pkg_branch = $(strip															\
		$(if $(filter %.git, $(pkg_url)),										\
			$(if $(strip														\
					$(word 2,													\
						$(subst ^, ,$(pkg_urn))									\
					)															\
				 ),																\
				$(word 2,														\
					$(subst ^, ,$(pkg_urn))										\
				)																\
			)																	\
		)																		\
	)
# Create a shell command for downloading package (if necessary).
# Either wget for tarballs or git clone. Optionaly we checkout
# a specific GIT branch/tag.
pkg_fetch = $(strip																\
		$(if $(findstring ::,$(pkg_urn)),										\
			$(error Error; remove the colon character from recipe $(pkg_urn))	\
		)																		\
		$(or																	\
			$(if $(wildcard $(pkg_url)),										\
				:																\
			),																	\
			$(if $(findstring .tar.,$(pkg_url)),								\
				if ! wget --no-check-certificate								\
						-O "$(PKG_VER).tar$(suffix $(pkg_urn))"					\
						"$(pkg_url)"; then										\
					rm -f "$(PKG_VER).tar$(suffix $(pkg_urn))";					\
					exit 1;														\
				fi;																\
				echo "$(PKG_VER).tar$(suffix $(pkg_urn))"						\
					>>"$(PKG_VER)/.nard-generated"								\
			),																	\
			$(if $(filter %.git, $(pkg_url)),									\
				(git clone														\
					$(if $(findstring @,$(pkg_url)),							\
						$(shell echo $(subst /, ,$(pkg_url)) | awk '{			\
							printf "%s:",$$1;									\
							i = 2;												\
							while(i <= NF) {									\
								printf "/%s", $$i;								\
								i++												\
							};													\
						}'),													\
						$(pkg_url)												\
					)															\
					"$(PKG_VER)"												\
					$(if $(pkg_branch), && cd "$(PKG_VER)" &&					\
						( (git branch -a | grep -q "$(pkg_branch)" && git checkout -b "$(pkg_branch)" --track "origin/$(pkg_branch)") ||	\
						  (git tag -l | grep -q "$(pkg_branch)" && git checkout "$(pkg_branch)") || 										\
						  (git log -1 "$(pkg_branch)" | grep -q "$(pkg_branch)" && git checkout "$(pkg_branch)")							\
						)							\
					)															\
				) || exit														\
			),																	\
			echo No such file $(pkg_top)...; exit 1								\
		)																		\
	)

# Lib func for reversing a list of words
reverse = $(if $(wordlist 2,2,$(1)),$(call reverse, \
	$(wordlist 2,$(words $(1)),$(1))) $(firstword $(1)),$(1))

# Lib func for comparing equality of two words
eq = $(strip $(and $(findstring $(1),$(2)),$(findstring $(2),$(1))))

# Lib func for finding the path to the CURRENT executing
# makefile when it has been "included" (only).
curr_dir = $(dir $(word $(words $(MAKEFILE_LIST)),$(MAKEFILE_LIST)))

# Lib func of finding the name of the application the current
# executing makefile belongs to, when it has been "included" (only).
curr_name = $(word $(words $(subst /, ,$(curr_dir))),$(subst /, ,$(curr_dir)))
curr_app = $(curr_dir)$(curr_name)

# Lib func, a native Make "which" command
which = $(firstword $(wildcard $(addsuffix /$(strip $(1)),$(subst :, ,$(PATH)))))

# Lib func of searching $PATH and return error if the command is missing
requireProg = $(foreach cmd, $(1), $(if $(call which, $(cmd)),,					\
	$(error $(strip Error; the program "$(cmd)" is missing from your path,		\
	please install it from your Linux distribution))))

# Lib func of searching for a named development librarary we can link to
# and return error if it's missing from gcc standard search paths
requireLib = $(foreach lib, $(1), $(if $(firstword $(wildcard					\
	$(shell gcc -print-file-name=$(lib)) )),, $(error $(strip Error; the		\
	"$(lib)" development library is missing, please install it from your		\
	Linux distribution))))

# Lib func of searching nard/util/bin and return error if the command is missing
requireUtil = $(if $(wildcard $(PATH_UTIL)/bin/$(strip $(1))),,					\
		$(error $(strip Error; the program "$(strip $(2))" is missing			\
	 from your product recipe)))


# Lib func for extracting application tarballs
std-extract = 																	\
	test -d "$(PATH_SCRAP)" || mkdir -p "$(PATH_SCRAP)";						\
	echo "$(PKG_NAME) $(subst $(PKG_NAME)-,,$(PKG_VER))"						\
		>>$(PATH_SCRAP)/package-archives.log;									\
	$(pkg_fetch);																\
	test -d "$(PKG_VER)" || mkdir -p "$(PKG_VER)";								\
	if test -e "$(PKG_VER).tar."*; then											\
		tar --strip-components=1 -C "$(PKG_VER)"								\
			-xvf "$(PKG_VER).tar."* || exit;									\
	fi;																			\
	test -d "$(PKG_NAME)" || ln -s "$(PKG_VER)" "$(PKG_NAME)";					\
	touch "$@"

# Lib func for copying application top most config file to build dir
std-config = 																	\
	@for F in $(PKG_CONF); do													\
		if test -e "$$F"; then													\
			$(CP) -fvp "$$F" "$@";												\
		fi;																		\
	done;																		\
	if ! test -e "$@"; then														\
		echo "Missing file $(PKG_VER).config in $(PATH_PRODUCT)";				\
		false;																	\
	fi;

# Lib func for patching an application. Reads a list of
# patch file names from a .patchlist file in the app dir.
std-patch =																		\
	if test -f "$(PKG_VER).patchlist"; then										\
		source "$(PKG_VER).patchlist";											\
	elif test -f "$(PKG_NAME)-master.patchlist"; then							\
		source "$(PKG_NAME)-master.patchlist";									\
	fi;																			\
	if test -n "$$patches"; then												\
		(																		\
			cd "$(PKG_VER)";													\
			for p in $$patches; do												\
				echo "Applying patch $$p...";									\
				patch -p1 -b <"../$$p" || exit;									\
			done;																\
		);																		\
	fi;																			\
	touch "$@"

# Lib func for cleaning application builds
std-clean =																		\
	if test -d "$(PKG_NAME)" -o -L "$(PKG_NAME)"; then							\
		$(MAKE) -C "$(PKG_NAME)" clean;											\
		if test -e "$(PATH_FS)"; then											\
			find $(PATH_FS) -name ".nard-$(PKG_NAME)" -type f -delete;			\
			find $(PATH_FS) -name "$(PKG_NAME)" -type f -delete;				\
		fi;																		\
 	fi;																			\
	rm -rf ./*/.nard-build ./.nard-build ./*/staging

# Lib func for erasing application builds entirely
std-distclean =																	\
	if test -s "$(PKG_VER)/.nard-generated"; then								\
		rm -rf $$(<"$(PKG_VER)/.nard-generated");								\
	fi;																			\
	if test -L "$(PKG_NAME)"; then rm -rf $$(readlink -n "$(PKG_NAME)"); fi;	\
	if test -L "$(PKG_VER)"; then rm -rf $$(readlink -n "$(PKG_VER)"); fi;		\
	find -P -maxdepth 1 -type l -name "$(PKG_NAME)*" -delete;					\
	rm -rf "$(PKG_NAME)" "$(PKG_VER)" ./*/.nard-* ./.nard-*;					\
	if test -e "$(PATH_FS)"; then												\
		find $(PATH_FS) -name ".nard-$(PKG_NAME)" -type f -delete;				\
		find $(PATH_FS) -name "$(PKG_NAME)" -type f -delete;					\
	fi;

# Lib func for default application dependencies
# Uses find to speed up recursive search of modified sources.
std-deps = \
	$(PKG_VER)/.nard-extract Makefile											\
	$(if $(wildcard $(PKG_VER)/.nard-build),									\
		$(shell find -L "$(PKG_VER)/" -follow									\
			-cnewer "$(PKG_VER)/.nard-build" -type f							\
			! -wholename "$(PKG_VER)/staging/*"									\
		)																		\
	)																			\
	$(if																		\
		$(and																	\
			$(wildcard $(PKG_VER)/.nard-build),									\
			$(wildcard $(PKG_VER).patches)										\
		),																		\
		$(shell find -L "$(PKG_VER).patches/" -follow							\
			-cnewer "$(PKG_VER)/.nard-build" -type f							\
		)																		\
	)																			\
	$(if																		\
		$(and																	\
			$(wildcard $(PKG_VER)/.nard-build),									\
			$(wildcard fs-template)												\
		),																		\
		$(shell find -L fs-template -follow										\
			-cnewer "$(PKG_VER)/.nard-build" -type f							\
		)																		\
	)



#------------------------------
# Before the user can build a specific product he
# needs to inform us which one. We save the choice to a
# generated makefile so he only needs to choose once.
ifneq ($(MAKECMDGOALS),distclean)

# Check some prerequisites before we start
# a product build the first time.
ifeq ($(wildcard $(PATH_INTER)/product.mk),)
ifeq ($(MAKECMDGOALS),)
$(info *********************************************)
$(info * You haven't choosen which product to build)
$(info * for! Go back to $(PATH_TOP))
$(info * and run "make skeleton" or similar!)
$(info *********************************************)
$(error No product choosen)
else	# No product choosen and MAKECMDGOALS not empty

# Check that we are using Bash as shell
ifeq ($(shell echo -n $$BASH_VERSION),)
$(error Bash is reqired for building Nard SDK, \
	please install it from your Linux distribution)
endif

# Check that we have found the top level directory
ifeq ($(wildcard $(PATH_TOP)/Rules.mk),)
$(error You are in wrong directory ($(PATH_TOP)))
endif

# Search the system for programs we know we need
requiredProgs := $(shell														\
	PATH=$(PATH);																\
	for P in dc head tail file grep cut tee nice ionice							\
		wc gawk sed dd rm cp bash chmod makedepend bzip2						\
		tr md5sum tar touch rsync zic gcc gzip mv ping							\
		dirname bison flex gperf automake libtool ip ssh						\
		depmod socat getconf patch find test curl scp							\
		xargs sha1sum wget install ln cmp env chroot							\
		sort sleep ar id strings getent tty tac ldconfig						\
		renice readlink makeinfo g++ autoconf chrt; do							\
		if ! command -v $${P} >/dev/null; then									\
			echo -n "$${P}, ";													\
		fi; 																	\
	done)
ifneq ($(requiredProgs),)
$(error The programs $(requiredProgs) is missing from your path,				\
	please install them from your Linux distribution)
endif

# Search the system for librarys we know we need
requiredLibs := $(shell															\
	PATH=$(PATH);																\
	for L in libcap.so libexpat.so libX11.so libc.so libncurses.so; do			\
		if ! test -e $$(gcc -print-file-name=$${L}); then						\
			echo -n "$${L}";													\
			break;																\
		fi;																		\
	done)
ifneq ($(requiredLibs),)
$(error The "$(requiredLibs)" development library is missing, \
	please install it from your Linux distribution)
endif

endif
endif																			# No product choosen



#-----------------------------
.PHONY: all
all:																			# First rule seen

# Generate a product definition file
.PHONY: product
product: $(PATH_INTER)/product.mk
$(PATH_INTER)/product.mk:
	@if test $$UID -eq 0; then													\
		echo "***** Warning: Don't build this system as root!";					\
		exit 1;																	\
	fi
	@if echo clean | grep -q "$(MAKECMDGOALS)"; then false; fi					# Stop processing here if doing a big clean
	@# Check that user is building a product we know of
	@if ! grep -qE "^PRODUCT_DEPS|^BOARD[^_]+"									\
			"$(PATH_TOP)/platform/$(strip $(MAKECMDGOALS))/Rules.mk"			\
			2>/dev/null; then													\
		echo "*********************************************";					\
		echo "No such product $(MAKECMDGOALS)! Please choose one of these:";	\
		grep -lE "^PRODUCT_DEPS|^BOARD[^_]+" platform/*/Rules.mk |				\
			sed -re "s/^[^/]+\//\t/g" -e "s/\/[^/]+//g";						\
		echo "*********************************************";					\
		exit 1;																	\
	fi
	@echo "Building product $(MAKECMDGOALS)"
	test -d "$(PATH_INTER)" || mkdir -p "$(PATH_INTER)"
	echo "# // Autogenerated file, describes built board & product"				\
		>"$(PATH_INTER)/product.mk.tmp"
	echo "export PRODUCT := $(strip $(MAKECMDGOALS))"							\
		>>"$(PATH_INTER)/product.mk.tmp"
	echo "export PRODUCT_DEPS := $(strip $(MAKECMDGOALS))"						\
		>>"$(PATH_INTER)/product.mk.tmp"
	echo "include $(PATH_TOP)/platform/\$$(PRODUCT)/Rules.mk"					\
		>>"$(PATH_INTER)/product.mk.tmp"
	echo "\$$(PRODUCT): all" >>"$(PATH_INTER)/product.mk.tmp"
	mv -vf "$(PATH_INTER)/product.mk.tmp" "$(PATH_INTER)/product.mk"

# Generate a board definition file
.PHONY: board
board: $(PATH_INTER)/board.mk
$(PATH_INTER)/board.mk:
	@if test -n "$(strip $(BOARD))" -a -d "$(PATH_INTER)"; then					\
		echo "# // Autogenerated file, describes built board & product"			\
			>"$(PATH_INTER)/board.mk.tmp";										\
		echo "export BOARD := $(BOARD)" >>"$(PATH_INTER)/board.mk.tmp";			\
		echo "export BOARD_DEPS := $(strip $(BOARD))"							\
			>>"$(PATH_INTER)/board.mk.tmp";										\
		echo "include $(PATH_TOP)/platform/\$$(BOARD)/Rules.mk"					\
			>>"$(PATH_INTER)/board.mk.tmp";										\
		mv -vf "$(PATH_INTER)/board.mk.tmp" "$(PATH_INTER)/board.mk";			\
	fi
endif																			# The target invoked was not distclean


#-----------------------------													# Standard targets
force:																			# Targets dependant of "force" will always be rebuilt
.DELETE_ON_ERROR:
.SUFFIXES:																		# Disable suffix implicit rules


#-----------------------------
# Get defines which tell what 
# hw and sw we use and thus need.
-include $(PATH_INTER)/product.mk
-include $(PATH_INTER)/board.mk
include $(PATH_TOP)/platform/default/Rules.mk

# Check for common user error where a ":" is incorrectly in the
# product recipes. This must be done after includes above.
ifneq ($(findstring :,$(PKGS_APPS) $(PKGS_UTILS)),)
$(error Error; remove the colon character from product recipe)
endif

