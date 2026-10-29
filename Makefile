#---------------------------------------------------------------------------------
.SUFFIXES:
#---------------------------------------------------------------------------------

ifeq ($(strip $(DEVKITARM)),)
$(error "Please set DEVKITARM in your environment. export DEVKITARM=<path to>devkitARM")
endif

TOPDIR ?= $(CURDIR)
include $(DEVKITARM)/3ds_rules

rwildcard = $(foreach d, $(wildcard $1*), \
            $(filter $(subst *, %, $2), $d) \
            $(call rwildcard, $d/, $2))

define unique =
  $(eval seen :=)
  $(foreach _, $1, $(if $(filter $_,${seen}),,$(eval seen += $_)))
  ${seen}
endef
#---------------------------------------------------------------------------------
# TARGET is the name of the output
# BUILD is the directory where object files & intermediate files will be placed
# SOURCES is a list of directories containing source code
# DATA is a list of directories containing data files
# INCLUDES is a list of directories containing header files
# GRAPHICS is a list of directories containing graphics files
# GFXBUILD is the directory where converted graphics files will be placed
#   If set to $(BUILD), it will statically link in the converted
#   files as if they were data files.
#
# NO_SMDH: if set to anything, no SMDH file is generated.
# ROMFS is the directory which contains the RomFS, relative to the Makefile (Optional)
# APP_TITLE is the name of the app stored in the SMDH file (Optional)
# APP_DESCRIPTION is the description of the app stored in the SMDH file (Optional)
# APP_AUTHOR is the author of the app stored in the SMDH file (Optional)
# ICON is the filename of the icon (.png), relative to the project folder.
#   If not set, it attempts to use one of the following (in this order):
#     - <Project name>.png
#     - icon.png
#     - <libctru folder>/default_icon.png
#---------------------------------------------------------------------------------
TARGET		:=	$(notdir $(CURDIR))
BUILD		:=	build
SOURCE		:=	source
DATA		:=	data
INCLUDES	:=	source
GRAPHICS	:=	gfx
ROMFS		:=	romfs
LIBRARY := library
GFXBUILD	:=	$(ROMFS)/gfx
TIME := $(shell date +"%Y-%m-%d %H:%M:%S %Z")
#---------------------------------------------------------------------------------
APP_VER					:= 84
APP_TITLE				:= FourthTube
APP_DESCRIPTION				:= A YouTube Client For The 3DS
APP_AUTHOR				:= The FourthTube Community
PRODUCT_CODE				:= CTR-TYT
UNIQUE_ID				:= 0xBF74D

BANNER_AUDIO				:= resource/banner.wav
BANNER_IMAGE				:= resource/banner.cgfx
ICON        				:= resource/icon.png
RSF_PATH				:= resource/app.rsf

LOGO                :=	resource/logo.bin

#---------------------------------------------------------------------------------
#---------------------------------------------------------------------------------
# options for code generation
#---------------------------------------------------------------------------------
ARCH	:=	-march=armv6k -mtune=mpcore -mfloat-abi=hard -mtp=soft

CFLAGS	:= -Wall -Wextra -Wno-unused -Wno-psabi -O2 -mword-relocations \
		-fomit-frame-pointer -ffunction-sections -fdata-sections \
		$(ARCH) -DDEF_BUILD_TIME="\"$(TIME)\""

CFLAGS	+=	$(INCLUDE) -DARM11 -D__3DS__ -DCURL_STATICLIB

ifneq ($(strip $(DIAG)),)
CFLAGS	+=	-DDEF_DIAG_BUILD -DDEF_DIAG_BUILD_ID="\"$(DIAG_BUILD_ID)\""
CFLAGS	+=	-DOPENTUBE_VERSION_MAJOR=0 -DOPENTUBE_VERSION_MINOR=$(OPENTUBE_VERSION_MINOR) \
		-DOPENTUBE_VERSION_MICRO=$(OPENTUBE_VERSION_MICRO)
ifneq ($(strip $(DIAG_FPS)),0)
CFLAGS	+=	-DDEF_FPS_DIAG
endif
endif

# Keep compile-time __FILE__ in our app objects independent of the local build path.
CFLAGS	+= -fmacro-prefix-map=$(TOPDIR)=/src/opentube
CXXFLAGS	:= $(CFLAGS) -fno-exceptions -std=gnu++14

ASFLAGS	:= $(ARCH)
LDFLAGS	= 	-specs=3dsx.specs $(ARCH) -Wl,-Map,$(notdir $*.map)
# serialize libctru's lock-free linear heap allocator across threads (source/system/libctru_wrapper.cpp)
LDFLAGS	+=	-Wl,--wrap=linearAlloc,--wrap=linearMemAlign,--wrap=linearFree,--wrap=linearSpaceFree
ifneq ($(strip $(DIAG)),)
# restore the bundled fork's heap/linear heap split on top of the installed libctru (source/system/heap_split.cpp)
LDFLAGS	+=	-Wl,--wrap=__system_allocateHeaps
endif

LIBS	:= -lavfilter -lswresample -lavformat -lswscale -lavcodec -lavutil -lcurl -lbrotli -lnghttp2 -lmbedtls -lmbedx509 -lmbedcrypto -lz  -lcitro2d -lcitro3d -lctru -lm

#---------------------------------------------------------------------------------
# list of directories containing libraries, this must be the top level containing
# include and lib
#---------------------------------------------------------------------------------
LIBDIRS := library/FFmpeg library/libctru library/libbrotli library/libcurl library/nghttp2
LIBDIRS_DEVKITPRO := libctru portlibs/3ds

# Diagnostic builds compile against and link the INSTALLED libctru ($(DEVKITPRO)/libctru, paired with the
# installed newlib/libsysbase) instead of the bundled fork in library/libctru: the fork was built against an
# older newlib whose `struct _reent` layout differs (deviceData at 0x13c vs 0x1fc), which crashed revision 2
# at startup in romfs_open. Verified by scripts/check_abi_pairing.py after every diag build. Normal builds
# are unchanged.
ifneq ($(strip $(DIAG)),)
LIBDIRS := $(filter-out library/libctru,$(LIBDIRS))
endif

#---------------------------------------------------------------------------------
# no real need to edit anything past this point unless you need to add additional
# rules for different file extensions
#---------------------------------------------------------------------------------
ifneq ($(BUILD),$(notdir $(CURDIR)))
#---------------------------------------------------------------------------------

export OUTPUT	:=	$(CURDIR)/$(TARGET)
export TOPDIR	:=	$(CURDIR)

export VPATH	:= $(CURDIR)/$(SOURCE)

export DEPSDIR	:=	$(CURDIR)/$(BUILD)

CFILES		:=	$(patsubst $(SOURCE)/%, %, $(call rwildcard, $(SOURCE), *.c))
CPPFILES	:=	$(patsubst $(SOURCE)/%, %, $(call rwildcard, $(SOURCE), *.cpp))
SFILES		:=	$(patsubst $(SOURCE)/%, %, $(call rwildcard, $(SOURCE), *.s))
PICAFILES	:=	$(patsubst $(SOURCE)/%, %, $(call rwildcard, $(SOURCE), *.v.pica))
SHLISTFILES	:=	$(patsubst $(SOURCE)/%, %, $(call rwildcard, $(SOURCE), *.shlist))
GFXFILES	:=	$(call rwildcard, $(GRAPHICS), *.t3s)
BINFILES	:=	$(call rwildcard, $(DATA), *.*)



#---------------------------------------------------------------------------------
# use CXX for linking C++ projects, CC for standard C
#---------------------------------------------------------------------------------
ifeq ($(strip $(CPPFILES)),)
#---------------------------------------------------------------------------------
	export LD	:=	$(CC)
#---------------------------------------------------------------------------------
else
#---------------------------------------------------------------------------------
	export LD	:=	$(CXX)
#---------------------------------------------------------------------------------
endif
#---------------------------------------------------------------------------------

#---------------------------------------------------------------------------------
ifeq ($(GFXBUILD),$(BUILD))
#---------------------------------------------------------------------------------
export T3XFILES :=  $(GFXFILES:.t3s=.t3x)
#---------------------------------------------------------------------------------
else
export ROMFS_T3XFILES	:=	$(patsubst %.t3s, $(GFXBUILD)/%.t3x, $(GFXFILES))
export T3XHFILES		:=	$(patsubst %.t3s, $(BUILD)/%.h, $(GFXFILES))
#---------------------------------------------------------------------------------
endif
#---------------------------------------------------------------------------------

export OFILES_SOURCES 	:=	$(CPPFILES:.cpp=.o) $(CFILES:.c=.o) $(SFILES:.s=.o)
# $(sort) also removes duplicates and, unlike the `define unique =` helper above, works on GNU make 3.81 (macOS)
export OBJDIRS			:=	$(sort $(patsubst %, $(BUILD)/%, $(dir $(OFILES_SOURCES))))

export OFILES_BIN	:=	$(addsuffix .o,$(BINFILES)) \
			$(PICAFILES:.v.pica=.shbin.o) $(SHLISTFILES:.shlist=.shbin.o) \
			$(addsuffix .o,$(T3XFILES))

export OFILES := $(OFILES_BIN) $(OFILES_SOURCES)

export HFILES	:=	$(PICAFILES:.v.pica=_shbin.h) $(SHLISTFILES:.shlist=_shbin.h) \
			$(addsuffix .h,$(subst .,_,$(BINFILES))) \
			$(GFXFILES:.t3s=.h)

export INCLUDE	:=	$(foreach dir,$(INCLUDES),-I$(CURDIR)/$(dir)) \
			$(foreach dir,$(LIBDIRS),-I$(CURDIR)/$(dir)/include) \
			$(foreach dir,$(LIBDIRS_DEVKITPRO),-I$(DEVKITPRO)/$(dir)/include) \
			-I$(CURDIR)/$(LIBRARY) \
			-I$(CURDIR)/$(BUILD)

export LIBPATHS	:=	$(foreach dir,$(LIBDIRS),-L$(CURDIR)/$(dir)/lib) $(foreach dir,$(LIBDIRS_DEVKITPRO),-L$(DEVKITPRO)/$(dir)/lib)

ifneq ($(strip $(DIAG)),)
ifeq ($(wildcard $(DEVKITPRO)/libctru/lib/libctru.a),)
$(error diag build links the installed libctru but $(DEVKITPRO)/libctru/lib/libctru.a is missing (install/point DEVKITPRO at a 3ds-dev toolchain))
endif
ifneq ($(wildcard $(CURDIR)/$(DIAG_CURL_LIBDIR)/libcurl.a),)
export LIBPATHS	:=	-L$(CURDIR)/$(DIAG_CURL_LIBDIR) $(LIBPATHS)
else ifeq ($(strip $(DIAG_ALLOW_BUNDLED_CURL)),)
$(error diag build needs the rebuilt libcurl at $(DIAG_CURL_LIBDIR)/libcurl.a (run scripts/build_curl_diag.sh); set DIAG_ALLOW_BUNDLED_CURL=1 to link the bundled mbedtls-2.16 build instead)
endif
endif

export _3DSXDEPS	:=	$(if $(NO_SMDH),,$(OUTPUT).smdh)

ifeq ($(strip $(ICON)),)
	icons := $(wildcard *.png)
	ifneq (,$(findstring $(TARGET).png,$(icons)))
		export APP_ICON := $(TOPDIR)/$(TARGET).png
	else
		ifneq (,$(findstring icon.png,$(icons)))
			export APP_ICON := $(TOPDIR)/icon.png
		endif
	endif
else
	export APP_ICON := $(TOPDIR)/$(ICON)
endif

ifeq ($(strip $(NO_SMDH)),)
	export _3DSXFLAGS += --smdh=$(CURDIR)/$(TARGET).smdh
endif

ifneq ($(ROMFS),)
	export _3DSXFLAGS += --romfs=$(CURDIR)/$(ROMFS)
endif

.PHONY: all clean check-tools

#---------------------------------------------------------------------------------
# The repo should work after a fresh clone if the 3DS packaging tools are installed in the
# devkitPro toolchain or placed in resource/tools/. FourthTube keeps the binaries in its own
# resource tree; OpenTube now prefers the repo-local wrappers and falls back to the system toolchain.
#---------------------------------------------------------------------------------
BUNDLED_MAKEROM := $(CURDIR)/resource/tools/makerom
BUNDLED_MAKEROM_WIN := $(CURDIR)/resource/tools/makerom.exe
BUNDLED_BANNERTOOL := $(CURDIR)/resource/tools/bannertool
BUNDLED_BANNERTOOL_WIN := $(CURDIR)/resource/tools/bannertool.exe

ifeq ($(strip $(MAKEROM)),)
  ifneq ($(wildcard $(BUNDLED_MAKEROM)),)
    MAKEROM ?= $(BUNDLED_MAKEROM)
  else ifneq ($(shell command -v makerom 2>/dev/null),)
    MAKEROM ?= $(shell command -v makerom 2>/dev/null)
  else ifneq ($(wildcard $(DEVKITPRO)/tools/bin/makerom),)
    MAKEROM ?= $(DEVKITPRO)/tools/bin/makerom
  else
    MAKEROM ?= $(BUNDLED_MAKEROM)
  endif
endif

ifeq ($(strip $(BANNERTOOL)),)
  ifneq ($(wildcard $(BUNDLED_BANNERTOOL)),)
    BANNERTOOL ?= $(BUNDLED_BANNERTOOL)
  else ifneq ($(shell command -v bannertool 2>/dev/null),)
    BANNERTOOL ?= $(shell command -v bannertool 2>/dev/null)
  else ifneq ($(wildcard $(DEVKITPRO)/tools/bin/bannertool),)
    BANNERTOOL ?= $(DEVKITPRO)/tools/bin/bannertool
  else
    BANNERTOOL ?= $(BUNDLED_BANNERTOOL)
  endif
endif

check-tools:
	@if [ ! -x "$(MAKEROM)" ] || [ ! -x "$(BANNERTOOL)" ]; then \
		echo "Missing 3DS packaging tools: makerom and/or bannertool."; \
		echo "Install devkitPro's 3DS toolchain or place the binaries in resource/tools/."; \
		echo "Current values:"; \
		echo "  MAKEROM=$(MAKEROM)"; \
		echo "  BANNERTOOL=$(BANNERTOOL)"; \
		exit 1; \
	fi

RSF_APP_TITLE ?= $(APP_TITLE)
MAKEROM_ARGS := -elf "$(OUTPUT).elf" -rsf "$(RSF_PATH)" -banner "$(BUILD)/banner.bnr" -icon "$(BUILD)/icon.icn" -DAPP_TITLE="$(RSF_APP_TITLE)" -DAPP_PRODUCT_CODE="$(PRODUCT_CODE)" -DAPP_UNIQUE_ID="$(UNIQUE_ID)"

ifneq ($(strip $(LOGO)),)
	MAKEROM_ARGS	+=	 -logo "$(LOGO)"
endif
ifneq ($(strip $(ROMFS)),)
	MAKEROM_ARGS	+=	 -DAPP_ROMFS="$(ROMFS)"
endif

#---------------------------------------------------------------------------------

all: check-tools $(BUILD) $(GFXBUILD) $(DEPSDIR) $(ROMFS_T3XFILES) $(T3XHFILES) $(OBJDIRS)
	@echo Building 3dsx...
	@$(MAKE) -j10 -s --no-print-directory -C $(BUILD) -f $(CURDIR)/Makefile
	@echo
	@echo Building cia...
ifeq ($(OS),Windows_NT)
	@$(BANNERTOOL_WIN) makebanner $(BANNER_IMAGE_ARG) $(BANNER_IMAGE) $(BANNER_AUDIO_ARG) $(BANNER_AUDIO) -o $(BUILD)/banner.bnr
	@$(BANNERTOOL_WIN) makesmdh -s "$(APP_TITLE)" -l "$(APP_DESCRIPTION)" -p "$(APP_AUTHOR)" -i $(APP_ICON) -o $(BUILD)/icon.icn
	@$(MAKEROM_WIN) -f cia -o $(OUTPUT)_dev.cia -target t -exefslogo $(MAKEROM_ARGS) -ver $(APP_VER)
else
	@$(BANNERTOOL) makebanner $(BANNER_IMAGE_ARG) $(BANNER_IMAGE) $(BANNER_AUDIO_ARG) $(BANNER_AUDIO) -o $(BUILD)/banner.bnr
	@$(BANNERTOOL) makesmdh -s "$(APP_TITLE)" -l "$(APP_DESCRIPTION)" -p "$(APP_AUTHOR)" -i $(APP_ICON) -o $(BUILD)/icon.icn
	@$(MAKEROM) -f cia -o $(OUTPUT)_dev.cia -target t -exefslogo $(MAKEROM_ARGS) -ver $(APP_VER)
endif

release: check-tools $(BUILD) $(GFXBUILD) $(DEPSDIR) $(ROMFS_T3XFILES) $(T3XHFILES) $(OBJDIRS)
	@echo -e "\033[0;33mThis target is intended for project maintainers to quickly create a file named FourthTube.cia to ship. You probably don't want this as a regular builder.\033[0m"
	@echo Building 3dsx...
	@$(MAKE) -j10 -s --no-print-directory -C $(BUILD) -f $(CURDIR)/Makefile
	@echo
	@echo Building cia...
ifeq ($(OS),Windows_NT)
	@$(BANNERTOOL_WIN) makebanner $(BANNER_IMAGE_ARG) $(BANNER_IMAGE) $(BANNER_AUDIO_ARG) $(BANNER_AUDIO) -o $(BUILD)/banner.bnr
	@$(BANNERTOOL_WIN) makesmdh -s "$(APP_TITLE)" -l "$(APP_DESCRIPTION)" -p "$(APP_AUTHOR)" -i $(APP_ICON) -o $(BUILD)/icon.icn
	@$(MAKEROM_WIN) -f cia -o $(OUTPUT).cia -target t -exefslogo $(MAKEROM_ARGS) -ver $(APP_VER)
else
	@$(BANNERTOOL) makebanner $(BANNER_IMAGE_ARG) $(BANNER_IMAGE) $(BANNER_AUDIO_ARG) $(BANNER_AUDIO) -o $(BUILD)/banner.bnr
	@$(BANNERTOOL) makesmdh -s "$(APP_TITLE)" -l "$(APP_DESCRIPTION)" -p "$(APP_AUTHOR)" -i $(APP_ICON) -o $(BUILD)/icon.icn
	@$(MAKEROM) -f cia -o $(OUTPUT).cia -target t -exefslogo $(MAKEROM_ARGS) -ver $(APP_VER)
endif

all_win:
	@echo -e "\033[0;33m\"make all_win\" is deprecated. Please just run \"make\" or \"make all\".\033[0m"
	@$(MAKE)

$(BUILD):
	@mkdir -p $@

ifneq ($(GFXBUILD),$(BUILD))
$(GFXBUILD):
	@mkdir -p $@
endif

ifneq ($(DEPSDIR),$(BUILD))
$(DEPSDIR):
	@mkdir -p $@
endif

$(OBJDIRS) 	:
	@mkdir -p $@

#---------------------------------------------------------------------------------
clean:
	@echo clean ...
	@rm -fr $(BUILD) $(TARGET).3dsx $(OUTPUT).smdh $(TARGET).elf $(TARGET)_dev.cia

#---------------------------------------------------------------------------------
$(GFXBUILD)/%.t3x	$(BUILD)/%.h	: 	%.t3s
#---------------------------------------------------------------------------------
	@echo $(notdir $<)
	@tex3ds -i $< -H $(BUILD)/$*.h -d $(DEPSDIR)/$*.d -o $(GFXBUILD)/$*.t3x

#---------------------------------------------------------------------------------
else

#---------------------------------------------------------------------------------
# main targets
#---------------------------------------------------------------------------------
$(OUTPUT).3dsx	: 	$(OUTPUT).elf $(_3DSXDEPS)

$(OUTPUT).elf	: 	$(OFILES)


#---------------------------------------------------------------------------------
# you need a rule like this for each extension you use as binary data
#---------------------------------------------------------------------------------
%.bin.o	%_bin.h :	%.bin
#---------------------------------------------------------------------------------
	@echo $(notdir $<)
	@$(bin2o)

#---------------------------------------------------------------------------------
.PRECIOUS	: 	%.t3x
#---------------------------------------------------------------------------------
%.t3x.o	%_t3x.h :	%.t3x
#---------------------------------------------------------------------------------
	@echo $(notdir $<)
	@$(bin2o)

#---------------------------------------------------------------------------------
# rules for assembling GPU shaders
#---------------------------------------------------------------------------------
define shader-as
	$(eval CURBIN := $*.shbin)
	$(eval DEPSFILE := $(DEPSDIR)/$*.shbin.d)
	echo "$(CURBIN).o: $< $1" > $(DEPSFILE)
	echo "extern const u8" `(echo $(CURBIN) | sed -e 's/^\([0-9]\)/_\1/' | tr . _)`"_end[];" > `(echo $(CURBIN) | tr . _)`.h
	echo "extern const u8" `(echo $(CURBIN) | tr . _)`"[];" >> `(echo $(CURBIN) | tr . _)`.h
	echo "extern const u32" `(echo $(CURBIN) | sed -e 's/^\([0-9]\)/_\1/' | tr . _)`_size";" >> `(echo $(CURBIN) | tr . _)`.h
	picasso -o $(CURBIN) $1
	bin2s $(CURBIN) | $(AS) -o $*.shbin.o
endef

%.shbin.o %_shbin.h : %.v.pica %.g.pica
	@echo $(notdir $^)
	@$(call shader-as,$^)

%.shbin.o %_shbin.h : %.v.pica
	@echo $(notdir $<)
	@$(call shader-as,$<)

%.shbin.o %_shbin.h : %.shlist
	@echo $(notdir $<)
	@$(call shader-as,$(foreach file,$(shell cat $<),$(dir $<)$(file)))

#---------------------------------------------------------------------------------
%.t3x	%.h	: 	%.t3s
#---------------------------------------------------------------------------------
	@echo $(notdir $<)
	@tex3ds -i $< -H $*.h -d $*.d -o $*.t3x

-include $(call rwildcard, $(DEPSDIR), *.d)

#---------------------------------------------------------------------------------------
endif
#---------------------------------------------------------------------------------------
