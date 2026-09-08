# Native PDF processing build for Apple platforms.
#
# The caller extracts the upstream archives into ./sources and passes only
# values supplied by Xcode. This file intentionally uses no CMake, GN, Ninja,
# NASM, Homebrew package or downloaded compiler.

ifndef PLATFORM_KEY
$(error PLATFORM_KEY is required)
endif
ifndef SDK
$(error SDK is required)
endif
ifndef ARCH
$(error ARCH is required)
endif
ifndef TARGET_TRIPLE
$(error TARGET_TRIPLE is required)
endif
ifndef LINK_PLATFORM
$(error LINK_PLATFORM is required)
endif
ifndef DEPLOYMENT_TARGET
$(error DEPLOYMENT_TARGET is required)
endif

SHELL := /bin/bash
CC := $(shell xcrun --sdk $(SDK) --find clang)
CXX := $(shell xcrun --sdk $(SDK) --find clang++)
LD := $(shell xcrun --sdk $(SDK) --find ld)
LIBTOOL := $(shell xcrun --sdk $(SDK) --find libtool)
NMEDIT := $(shell xcrun --sdk $(SDK) --find nmedit)
SDKROOT := $(shell xcrun --sdk $(SDK) --show-sdk-path)
SDK_VERSION := $(shell xcrun --sdk $(SDK) --show-sdk-version)

# Match the existing Ghostscript build-phase behavior: keep upstream
# diagnostics in the build log, but prevent Xcode from turning third-party
# "warning:" lines into project navigator issues. `pipefail` preserves the
# compiler or archiver exit status. Native iPS2PDF sources do not use this
# filter, so warnings in project-owned code remain ordinary Xcode warnings.
UPSTREAM_DIAGNOSTIC_FILTER := 2>&1 | /usr/bin/sed -E 's/[Ww]arning:/warn:/g'

OBJECT_ROOT := build/$(PLATFORM_KEY)/objects
OUTPUT_ROOT := build/$(PLATFORM_KEY)/output
PDFIUM_SOURCE := sources/pdfium
QPDF_SOURCE := sources/qpdf
QPDF_JPEG_SOURCE := sources/qpdf-jpeg
JPEGLI_SOURCE := sources/jpegli
HIGHWAY_SOURCE := $(JPEGLI_SOURCE)/third_party/highway
NATIVE_SOURCE := sources/native

include recipes/PDFiumSources.mk
include recipes/QPDFSources.mk
include recipes/QPDFJPEGSources.mk
include recipes/JPEGLISources.mk

# Keep optimization and ABI choices in one place. PDFium itself is built as
# C++20; qpdf and the iPS2PDF adapter need exceptions for error propagation.
APPLE_FLAGS := -Os -DNDEBUG -fPIC -fvisibility=hidden -fno-strict-aliasing \
  -target $(TARGET_TRIPLE) -isysroot $(SDKROOT)
C_FLAGS := $(APPLE_FLAGS)
CXX_FLAGS := $(APPLE_FLAGS) -std=c++20 -fvisibility-inlines-hidden

PDFIUM_OBJECTS :=

define PDFIUM_GROUP_RULES
PDFIUM_GROUP_$(1)_OBJECTS := $$(addprefix $(OBJECT_ROOT)/pdfium/$(1)/,$$(addsuffix .o,$$(PDFIUM_GROUP_$(1)_SOURCES)))
PDFIUM_OBJECTS += $$(PDFIUM_GROUP_$(1)_OBJECTS)
$$(PDFIUM_GROUP_$(1)_OBJECTS): $(OBJECT_ROOT)/pdfium/$(1)/%.o: $(PDFIUM_SOURCE)/%
	@mkdir -p "$$(@D)"
	@set -o pipefail; $$(PDFIUM_GROUP_$(1)_COMPILER) $$(if $$(filter $$(CC),$$(PDFIUM_GROUP_$(1)_COMPILER)),$$(C_FLAGS),$$(CXX_FLAGS)) $$(PDFIUM_GROUP_$(1)_DEFINES) $$(PDFIUM_GROUP_$(1)_INCLUDES) -c "$$<" -o "$$@" $$(UPSTREAM_DIAGNOSTIC_FILTER)
endef
$(foreach group,$(PDFIUM_GROUPS),$(eval $(call PDFIUM_GROUP_RULES,$(group))))

PDFIUM_ARCHIVE := $(OUTPUT_ROOT)/libpdfium.a
$(PDFIUM_ARCHIVE): $(PDFIUM_OBJECTS)
	@mkdir -p "$(@D)"
	@echo "Archiving PDFium for $(PLATFORM_KEY)…"
	@set -o pipefail; $(LIBTOOL) -static -o "$@" $(PDFIUM_OBJECTS) $(UPSTREAM_DIAGNOSTIC_FILTER)

QPDF_JPEG_COMMON := $(C_FLAGS) '-Igenerated/qpdf-jpeg' '-I$(QPDF_JPEG_SOURCE)/src' \
  -include recipes/Config/qpdf-jpeg-namespace.h
QPDF_JPEG_8_OBJECTS := $(addprefix $(OBJECT_ROOT)/qpdf-jpeg/8/,$(addsuffix .o,$(QPDF_JPEG_8_SOURCES)))
QPDF_JPEG_12_OBJECTS := $(addprefix $(OBJECT_ROOT)/qpdf-jpeg/12/,$(addsuffix .o,$(QPDF_JPEG_12_SOURCES)))
QPDF_JPEG_16_OBJECTS := $(addprefix $(OBJECT_ROOT)/qpdf-jpeg/16/,$(addsuffix .o,$(QPDF_JPEG_16_SOURCES)))
QPDF_JPEG_OBJECTS := $(QPDF_JPEG_8_OBJECTS) $(QPDF_JPEG_12_OBJECTS) $(QPDF_JPEG_16_OBJECTS)

$(QPDF_JPEG_8_OBJECTS): $(OBJECT_ROOT)/qpdf-jpeg/8/%.o: $(QPDF_JPEG_SOURCE)/%
	@mkdir -p "$(@D)"
	@set -o pipefail; $(CC) $(QPDF_JPEG_COMMON) -c "$<" -o "$@" $(UPSTREAM_DIAGNOSTIC_FILTER)
$(QPDF_JPEG_12_OBJECTS): $(OBJECT_ROOT)/qpdf-jpeg/12/%.o: $(QPDF_JPEG_SOURCE)/%
	@mkdir -p "$(@D)"
	@set -o pipefail; $(CC) $(QPDF_JPEG_COMMON) -DBITS_IN_JSAMPLE=12 -c "$<" -o "$@" $(UPSTREAM_DIAGNOSTIC_FILTER)
$(QPDF_JPEG_16_OBJECTS): $(OBJECT_ROOT)/qpdf-jpeg/16/%.o: $(QPDF_JPEG_SOURCE)/%
	@mkdir -p "$(@D)"
	@set -o pipefail; $(CC) $(QPDF_JPEG_COMMON) -DBITS_IN_JSAMPLE=16 -c "$<" -o "$@" $(UPSTREAM_DIAGNOSTIC_FILTER)

QPDF_JPEG_ARCHIVE := $(OUTPUT_ROOT)/libqpdf-jpeg.a
$(QPDF_JPEG_ARCHIVE): $(QPDF_JPEG_OBJECTS)
	@mkdir -p "$(@D)"
	@echo "Archiving qpdf JPEG for $(PLATFORM_KEY)…"
	@set -o pipefail; $(LIBTOOL) -static -o "$@" $(QPDF_JPEG_OBJECTS) $(UPSTREAM_DIAGNOSTIC_FILTER)

QPDF_C_SOURCES := $(filter %.c,$(QPDF_SOURCES))
QPDF_CXX_SOURCES := $(filter-out %.c,$(QPDF_SOURCES))
QPDF_C_OBJECTS := $(addprefix $(OBJECT_ROOT)/qpdf/,$(addsuffix .o,$(QPDF_C_SOURCES)))
QPDF_CXX_OBJECTS := $(addprefix $(OBJECT_ROOT)/qpdf/,$(addsuffix .o,$(QPDF_CXX_SOURCES)))
QPDF_OBJECTS := $(QPDF_CXX_OBJECTS) $(QPDF_C_OBJECTS)
QPDF_FLAGS := $(CXX_FLAGS) -DQPDF_DISABLE_QTC=1 '-I$(QPDF_SOURCE)/include' \
  '-I$(QPDF_SOURCE)/libqpdf' '-Igenerated/qpdf' '-Igenerated/qpdf-jpeg' \
  '-I$(QPDF_JPEG_SOURCE)/src' \
  -include recipes/Config/qpdf-jpeg-namespace.h
$(QPDF_CXX_OBJECTS): $(OBJECT_ROOT)/qpdf/%.o: $(QPDF_SOURCE)/%
	@mkdir -p "$(@D)"
	@set -o pipefail; $(CXX) $(QPDF_FLAGS) -c "$<" -o "$@" $(UPSTREAM_DIAGNOSTIC_FILTER)
$(QPDF_C_OBJECTS): $(OBJECT_ROOT)/qpdf/%.o: $(QPDF_SOURCE)/%
	@mkdir -p "$(@D)"
	@set -o pipefail; $(CC) $(C_FLAGS) -DQPDF_DISABLE_QTC=1 '-I$(QPDF_SOURCE)/include' \
	  '-I$(QPDF_SOURCE)/libqpdf' '-Igenerated/qpdf' -c "$<" -o "$@" $(UPSTREAM_DIAGNOSTIC_FILTER)

QPDF_ARCHIVE := $(OUTPUT_ROOT)/libqpdf.a
$(QPDF_ARCHIVE): $(QPDF_OBJECTS)
	@mkdir -p "$(@D)"
	@echo "Archiving qpdf for $(PLATFORM_KEY)…"
	@set -o pipefail; $(LIBTOOL) -static -o "$@" $(QPDF_OBJECTS) $(UPSTREAM_DIAGNOSTIC_FILTER)

# jpegli gives materially better JPEG output at a given size. Highway is built
# from its own source archive and supplies jpegli's portable SIMD dispatch.
HIGHWAY_DEFINES := -DFJXL_ENABLE_AVX512=0 -DHWY_STATIC_DEFINE \
  -DTOOLCHAIN_MISS_ASM_HWCAP_H -DTOOLCHAIN_MISS_SYS_AUXV_H \
  '-DHWY_DISABLED_TARGETS=(HWY_SSSE3|HWY_AVX3|HWY_AVX3_SPR|HWY_AVX3_ZEN4|HWY_SVE|HWY_SVE2|HWY_SVE_256|HWY_SVE2_128|HWY_RVV)'
HIGHWAY_OBJECTS := $(addprefix $(OBJECT_ROOT)/highway/,$(addsuffix .o,$(HIGHWAY_SOURCES)))
$(HIGHWAY_OBJECTS): $(OBJECT_ROOT)/highway/%.o: $(HIGHWAY_SOURCE)/%
	@mkdir -p "$(@D)"
	@set -o pipefail; $(CXX) $(CXX_FLAGS) $(HIGHWAY_DEFINES) '-I$(HIGHWAY_SOURCE)' -c "$<" -o "$@" $(UPSTREAM_DIAGNOSTIC_FILTER)

HIGHWAY_ARCHIVE := $(OUTPUT_ROOT)/libhwy.a
$(HIGHWAY_ARCHIVE): $(HIGHWAY_OBJECTS)
	@mkdir -p "$(@D)"
	@set -o pipefail; $(LIBTOOL) -static -o "$@" $(HIGHWAY_OBJECTS) $(UPSTREAM_DIAGNOSTIC_FILTER)

JPEGLI_DEFINES := $(HIGHWAY_DEFINES) -DJPEGXL_ENABLE_SKCMS=1 \
  -DJPEGXL_ENABLE_TRANSCODE_JPEG=0 -DJPEGXL_ENABLE_BOXES=1
JPEGLI_INCLUDES := '-I$(JPEGLI_SOURCE)' '-I$(JPEGLI_SOURCE)/lib/include' \
  '-Igenerated/jpegli' '-I$(HIGHWAY_SOURCE)'
JPEGLI_OBJECTS := $(addprefix $(OBJECT_ROOT)/jpegli/,$(addsuffix .o,$(JPEGLI_SOURCES)))
$(JPEGLI_OBJECTS): $(OBJECT_ROOT)/jpegli/%.o: $(JPEGLI_SOURCE)/%
	@mkdir -p "$(@D)"
	@set -o pipefail; $(CXX) $(CXX_FLAGS) $(JPEGLI_DEFINES) $(JPEGLI_INCLUDES) -c "$<" -o "$@" $(UPSTREAM_DIAGNOSTIC_FILTER)

JPEGLI_ARCHIVE := $(OUTPUT_ROOT)/libjpegli.a
$(JPEGLI_ARCHIVE): $(JPEGLI_OBJECTS)
	@mkdir -p "$(@D)"
	@set -o pipefail; $(LIBTOOL) -static -o "$@" $(JPEGLI_OBJECTS) $(UPSTREAM_DIAGNOSTIC_FILTER)

HYPER_JPEGLI_OBJECT := $(OBJECT_ROOT)/adapter/hyper_jpegli_wrap.o
$(HYPER_JPEGLI_OBJECT): sources/hyper/core/src/hyper_jpegli_wrap.cc
	@mkdir -p "$(@D)"
	@set -o pipefail; $(CXX) $(CXX_FLAGS) $(JPEGLI_INCLUDES) -c "$<" -o "$@" $(UPSTREAM_DIAGNOSTIC_FILTER)

NATIVE_SOURCES := $(sort $(wildcard $(NATIVE_SOURCE)/*.cpp))
NATIVE_OBJECTS := $(patsubst $(NATIVE_SOURCE)/%.cpp,$(OBJECT_ROOT)/native/%.o,$(NATIVE_SOURCES))
NATIVE_INCLUDES := '-I$(NATIVE_SOURCE)' \
  -isystem '$(QPDF_SOURCE)/include' -isystem '$(QPDF_SOURCE)/libqpdf' -isystem 'generated/qpdf' \
  -isystem 'generated/qpdf-jpeg' -isystem '$(PDFIUM_SOURCE)' \
  -isystem '$(PDFIUM_SOURCE)/third_party/leptonica/src' \
  -isystem '$(JPEGLI_SOURCE)' -isystem '$(JPEGLI_SOURCE)/lib/include' -isystem 'generated/jpegli' \
  -isystem '$(SDKROOT)/usr/include/libxml2'
$(NATIVE_OBJECTS): $(OBJECT_ROOT)/native/%.o: $(NATIVE_SOURCE)/%.cpp
	@mkdir -p "$(@D)"
	@$(CXX) $(CXX_FLAGS) $(NATIVE_INCLUDES) -c "$<" -o "$@"

COMBINED_OBJECT := $(OUTPUT_ROOT)/PDFProcessingCombined.o
$(COMBINED_OBJECT): $(PDFIUM_ARCHIVE) $(QPDF_ARCHIVE) $(QPDF_JPEG_ARCHIVE) \
    $(JPEGLI_ARCHIVE) $(HIGHWAY_ARCHIVE) $(HYPER_JPEGLI_OBJECT) $(NATIVE_OBJECTS)
	@echo "Combining and isolating native PDF symbols for $(PLATFORM_KEY)…"
	@$(LD) -r -arch $(ARCH) -platform_version $(LINK_PLATFORM) \
	  $(DEPLOYMENT_TARGET) $(SDK_VERSION) -syslibroot $(SDKROOT) -o "$@" \
	  $(NATIVE_OBJECTS) $(HYPER_JPEGLI_OBJECT) \
	  -force_load $(PDFIUM_ARCHIVE) -force_load $(JPEGLI_ARCHIVE) \
	  -force_load $(HIGHWAY_ARCHIVE) -force_load $(QPDF_ARCHIVE) \
	  -force_load $(QPDF_JPEG_ARCHIVE)

ISOLATED_OBJECT := $(OUTPUT_ROOT)/PDFProcessingIsolated.o
$(ISOLATED_OBJECT): $(COMBINED_OBJECT) recipes/Config/public-symbols.txt
	@$(NMEDIT) -s recipes/Config/public-symbols.txt "$<" -o "$@"

FINAL_ARCHIVE := $(OUTPUT_ROOT)/libPDFProcessingNative.a
$(FINAL_ARCHIVE): $(ISOLATED_OBJECT)
	@$(LIBTOOL) -static -o "$@" "$<"

.PHONY: all
all: $(FINAL_ARCHIVE)
	@echo "Built $(FINAL_ARCHIVE)"
