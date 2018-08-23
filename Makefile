
# Nard Linux SDK
# http://www.arbetsmyra.dyndns.org/nard
# Copyright (C) 2014-2017 Ronny Nilsson


include Rules.mk												# Common used stuff


PKGS := apps util images platform								# Packages (subdirs) we will go inside and make
CLEANPKGS := $(foreach PKG,$(PKGS), \
	$(patsubst %,%-clean,$(PKG)))
DISTCLEANPKGS := $(foreach PKG,$(PKGS), \
	$(patsubst %,%-distclean,$(PKG)))
PRODCLEANPKGS := \
	$(foreach PKG,$(filter-out util,$(PKGS)), \
		$(patsubst %,%-prodclean,$(PKG)))						# Exclude util subdir from productclean


#-----------------------------									# Standard targets
.PHONY: all
all: $(PKGS)

# Manual dependencies
images: platform
platform: apps
apps: util fs-template

# The rootfs template is part of platform and
# should be populated before the apps build.
# However, rest of platform should wait until
# after apps has been build, hence special handling.
.PHONY: fs-template
fs-template: $(PATH_INTER)/product.mk $(PATH_INTER)/board.mk
	$(MAKE) -C platform "$@"

# Build each subdir
.PHONY: $(PKGS)
$(PKGS): Makefile Rules.mk
$(PKGS): $(PATH_INTER)/product.mk $(PATH_INTER)/board.mk $(PATH_INTER)/board.h
	$(MAKE) -C "$@"



#----------------------------									# Utilities
utilCmds := ssh upgrade scan gdb upload download help ? test
utilCmd := $(strip $(foreach cmd,$(strip $(utilCmds)), \
	$(call eq,$(cmd),$(firstword $(strip $(MAKECMDGOALS))))))	# Which util command did user issue?

.PHONY: $(utilCmd)
$(utilCmd): $(PATH_INTER)/product.mk $(PATH_INTER)/board.mk
$(utilCmd): $(PATH_INTER)/board.h
	@exec $(PATH_UTIL)/bin/connect-nard-target "$(MAKECMDGOALS)"

ifneq ($(strip $(utilCmd)),)									# Disable Make smart features when invoking a utility
$(firstword $(strip $(MAKECMDGOALS))): force
.NOTPARALLEL:
.SUFFIXES:														# Disable implicit rules
.SILENT:														# Disable make's "xyz is up to date message"
%:																# Eat command line arguments destined for ssh
	@:															# Empty
endif


#----------------------------									# Cleaning	
.PHONY: $(CLEANPKGS)
$(CLEANPKGS):
	-$(MAKE) -k -C "$(subst -clean,,$@)" clean

.PHONY: $(DISTCLEANPKGS)
$(DISTCLEANPKGS):
	-$(MAKE) -k -C "$(subst -distclean,,$@)" distclean

$(PRODCLEANPKGS):												# Prepare for another product, but keep the toolchain as is
	-$(MAKE) -k -C "$(subst -prodclean,,$@)" distclean

.PHONY: clean
clean: $(CLEANPKGS)
	if test -d "$(PATH_INTER)"; then											\
		find "$(PATH_INTER)" -maxdepth 1 -mindepth 1							\
			-type d -exec rm -rf \{\} \;;										\
		find "$(PATH_INTER)" -type f -name "*.log" -delete;						\
	fi

.PHONY: distclean
distclean: $(DISTCLEANPKGS)
	if test -d "$(PATH_INTER)"; then rm -rf "$(PATH_INTER)"; fi


.PHONY: productclean
productclean: $(PRODCLEANPKGS)
	if test -d "$(PATH_INTER)"; then rm -rf "$(PATH_INTER)"; fi

