# Install Balloon into Windower as a symlink to this checkout, so edits here
# are live in game after //lua reload balloon.
#
#   make install     symlink this repo into Windower's addons folder
#   make uninstall   remove that symlink
#   make where       print the Windower folder that was found
#   make test        run the tests under luajit
#   make lint        run luacheck
#   make check       both
#   make native      build libs/balloonpad.dll (needs i686-w64-mingw32-gcc)
#
# The Windower folder is found automatically: the Lumoria flatpak prefix on
# Linux, else a plain Wine prefix. Set WINDOWER to point somewhere else:
#
#   make install WINDOWER=/path/to/Windower4

REPO := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
NAME := Balloon

# Candidate Windower folders, first match wins.
CANDIDATES := \
	$(wildcard $(HOME)/.var/app/net.windower.Lumoria/data/prefixes/*/pfx/drive_c/Windower4) \
	$(wildcard $(HOME)/.wine/drive_c/Windower4) \
	$(wildcard $(HOME)/.wine/drive_c/Windower)

WINDOWER ?= $(firstword $(CANDIDATES))
ADDONS := $(WINDOWER)/addons
LINK := $(ADDONS)/$(NAME)

# The gamepad module is a 32-bit Windows DLL linked against Windower's
# LuaCore.dll. Any Lua 5.1 compatible headers will do; LuaJIT's are 5.1.
CC32 ?= i686-w64-mingw32-gcc
LUA_INC ?= $(firstword $(wildcard \
	/home/linuxbrew/.linuxbrew/include/luajit-2.1 \
	/usr/include/luajit-2.1 \
	/usr/include/lua5.1 \
	/usr/include/lua-5.1))
LUACORE := $(WINDOWER)/plugins/LuaCore.dll

.PHONY: install uninstall where test lint check native

# Each recipe below is one shell command, so an exit inside it ends the target.

where:
	@if [ -z "$(WINDOWER)" ]; then \
		echo "No Windower install found. Set WINDOWER=/path/to/Windower4." >&2; exit 1; \
	fi; \
	echo "$(WINDOWER)"

install:
	@if [ -z "$(WINDOWER)" ]; then \
		echo "No Windower install found. Set WINDOWER=/path/to/Windower4." >&2; exit 1; \
	fi; \
	if [ ! -d "$(ADDONS)" ]; then \
		echo "$(ADDONS) is not a directory." >&2; exit 1; \
	fi; \
	if [ -L "$(LINK)" ]; then \
		if [ "$$(readlink -f "$(LINK)")" = "$(REPO)" ]; then \
			echo "$(LINK) already points here."; exit 0; \
		fi; \
		echo "Replacing symlink $(LINK) -> $$(readlink "$(LINK)")"; \
		unlink "$(LINK)"; \
	elif [ -e "$(LINK)" ]; then \
		echo "$(LINK) exists and is not a symlink." >&2; \
		echo "Move it aside (keep its data/settings.xml if you want it), then rerun." >&2; \
		exit 1; \
	fi; \
	ln -s "$(REPO)" "$(LINK)" && \
	echo "Installed $(LINK) -> $(REPO)" && \
	echo "In game: //lua load $(NAME)"

uninstall:
	@if [ -z "$(WINDOWER)" ]; then \
		echo "No Windower install found. Set WINDOWER=/path/to/Windower4." >&2; exit 1; \
	fi; \
	if [ -L "$(LINK)" ]; then unlink "$(LINK)" && echo "Removed $(LINK)"; \
	elif [ -e "$(LINK)" ]; then echo "$(LINK) is not a symlink; leaving it." >&2; exit 1; \
	else echo "Nothing installed at $(LINK)."; fi

test:
	luajit test/test_$(NAME).lua

native: libs/balloonpad.dll

libs/balloonpad.dll: native/balloonpad.c
	@if [ -z "$(LUA_INC)" ]; then echo "No Lua 5.1 headers found; set LUA_INC." >&2; exit 1; fi; \
	if [ ! -f "$(LUACORE)" ]; then echo "$(LUACORE) not found; set WINDOWER." >&2; exit 1; fi; \
	mkdir -p libs && \
	$(CC32) -O2 -Wall -shared -static-libgcc -o $@.tmp $< -I"$(LUA_INC)" "$(LUACORE)" -lxinput1_3 && \
	mv -f $@.tmp $@ && \
	echo "Built $@ (then //lua reload balloon in game)"

lint:
	luacheck .

check: lint test
