# Source manifest for the PDFium/Hyper Compress static library.
# Generated once from the pinned upstream GN graph; the checked-in build uses
# only Apple clang, make and libtool. Optional NASM/architecture SIMD sources
# are deliberately absent so the same recipe works on a clean Xcode install.

PDFIUM_GROUPS := 01 02 03 04 05 06 07 08 09 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25

PDFIUM_GROUP_01_COMPILER := $(CC)
PDFIUM_GROUP_01_DEFINES := '-DFT2_BUILD_LIBRARY' '-DNDEBUG' '-DNVALGRIND' '-DDYNAMIC_ANNOTATIONS_ENABLED=0' '-DOPJ_STATIC' '-DPDF_ENABLE_BROTLI' '-DPDF_USE_AGG' '-DFT_CONFIG_MODULES_H="freetype-custom-config/ftmodule.h"' '-DFT_CONFIG_OPTIONS_H="freetype-custom-config/ftoption.h"'
PDFIUM_GROUP_01_INCLUDES := '-I$(PDFIUM_SOURCE)' '-I$(PDFIUM_SOURCE)/third_party/freetype/include' '-I$(PDFIUM_SOURCE)/third_party/freetype/src/include'
PDFIUM_GROUP_01_SOURCES := \
  third_party/freetype/src/src/base/ftbase.c \
  third_party/freetype/src/src/base/ftbitmap.c \
  third_party/freetype/src/src/base/ftdebug.c \
  third_party/freetype/src/src/base/ftfstype.c \
  third_party/freetype/src/src/base/ftglyph.c \
  third_party/freetype/src/src/base/ftinit.c \
  third_party/freetype/src/src/base/ftmm.c \
  third_party/freetype/src/src/base/ftsystem.c \
  third_party/freetype/src/src/cff/cff.c \
  third_party/freetype/src/src/cid/type1cid.c \
  third_party/freetype/src/src/psaux/psaux.c \
  third_party/freetype/src/src/pshinter/pshinter.c \
  third_party/freetype/src/src/psnames/psmodule.c \
  third_party/freetype/src/src/raster/raster.c \
  third_party/freetype/src/src/sfnt/sfnt.c \
  third_party/freetype/src/src/smooth/smooth.c \
  third_party/freetype/src/src/truetype/truetype.c \
  third_party/freetype/src/src/type1/type1.c

PDFIUM_GROUP_02_COMPILER := $(CC)
PDFIUM_GROUP_02_DEFINES := '-DNDEBUG' '-DNVALGRIND' '-DDYNAMIC_ANNOTATIONS_ENABLED=0'
PDFIUM_GROUP_02_INCLUDES := '-I$(PDFIUM_SOURCE)' '-I$(PDFIUM_SOURCE)/third_party/brotli/include'
PDFIUM_GROUP_02_SOURCES := \
  third_party/brotli/dec/bit_reader.c \
  third_party/brotli/dec/decode.c \
  third_party/brotli/dec/huffman.c \
  third_party/brotli/dec/prefix.c \
  third_party/brotli/dec/state.c \
  third_party/brotli/dec/static_init.c \
  third_party/brotli/enc/backward_references.c \
  third_party/brotli/enc/backward_references_hq.c \
  third_party/brotli/enc/bit_cost.c \
  third_party/brotli/enc/block_splitter.c \
  third_party/brotli/enc/brotli_bit_stream.c \
  third_party/brotli/enc/cluster.c \
  third_party/brotli/enc/command.c \
  third_party/brotli/enc/compound_dictionary.c \
  third_party/brotli/enc/compress_fragment.c \
  third_party/brotli/enc/compress_fragment_two_pass.c \
  third_party/brotli/enc/dictionary_hash.c \
  third_party/brotli/enc/encode.c \
  third_party/brotli/enc/encoder_dict.c \
  third_party/brotli/enc/entropy_encode.c \
  third_party/brotli/enc/fast_log.c \
  third_party/brotli/enc/histogram.c \
  third_party/brotli/enc/literal_cost.c \
  third_party/brotli/enc/memory.c \
  third_party/brotli/enc/metablock.c \
  third_party/brotli/enc/static_dict.c \
  third_party/brotli/enc/static_dict_lut.c \
  third_party/brotli/enc/static_init.c \
  third_party/brotli/enc/utf8_util.c

PDFIUM_GROUP_03_COMPILER := $(CC)
PDFIUM_GROUP_03_DEFINES := '-DNDEBUG' '-DNVALGRIND' '-DDYNAMIC_ANNOTATIONS_ENABLED=0' '-DOPJ_STATIC' '-DPDF_ENABLE_BROTLI' '-DPDF_USE_AGG' '-DFT_CONFIG_MODULES_H="freetype-custom-config/ftmodule.h"' '-DFT_CONFIG_OPTIONS_H="freetype-custom-config/ftoption.h"' '-DU_USING_ICU_NAMESPACE=0' '-DU_ENABLE_DYLOAD=0' '-DUSE_CHROMIUM_ICU=1' '-DU_ENABLE_TRACING=1' '-DU_ENABLE_RESOURCE_TRACING=0' '-DU_STATIC_IMPLEMENTATION' '-DICU_UTIL_DATA_IMPL=ICU_UTIL_DATA_FILE'
PDFIUM_GROUP_03_INCLUDES := '-I$(PDFIUM_SOURCE)' '-I$(PDFIUM_SOURCE)/third_party/freetype/include' '-I$(PDFIUM_SOURCE)/third_party/freetype/src/include' '-I$(PDFIUM_SOURCE)/third_party/abseil-cpp' '-I$(PDFIUM_SOURCE)/third_party/icu/source/common' '-I$(PDFIUM_SOURCE)/third_party/icu/source/i18n'
PDFIUM_GROUP_03_SOURCES := \
  third_party/lcms/src/cmsalpha.c \
  third_party/lcms/src/cmscam02.c \
  third_party/lcms/src/cmscgats.c \
  third_party/lcms/src/cmscnvrt.c \
  third_party/lcms/src/cmserr.c \
  third_party/lcms/src/cmsgamma.c \
  third_party/lcms/src/cmsgmt.c \
  third_party/lcms/src/cmshalf.c \
  third_party/lcms/src/cmsintrp.c \
  third_party/lcms/src/cmsio0.c \
  third_party/lcms/src/cmsio1.c \
  third_party/lcms/src/cmslut.c \
  third_party/lcms/src/cmsmd5.c \
  third_party/lcms/src/cmsmtrx.c \
  third_party/lcms/src/cmsnamed.c \
  third_party/lcms/src/cmsopt.c \
  third_party/lcms/src/cmspack.c \
  third_party/lcms/src/cmspcs.c \
  third_party/lcms/src/cmsplugin.c \
  third_party/lcms/src/cmsps2.c \
  third_party/lcms/src/cmssamp.c \
  third_party/lcms/src/cmssm.c \
  third_party/lcms/src/cmstypes.c \
  third_party/lcms/src/cmsvirt.c \
  third_party/lcms/src/cmswtpnt.c \
  third_party/lcms/src/cmsxform.c \
  third_party/libopenjpeg/bio.c \
  third_party/libopenjpeg/cio.c \
  third_party/libopenjpeg/dwt.c \
  third_party/libopenjpeg/event.c \
  third_party/libopenjpeg/function_list.c \
  third_party/libopenjpeg/ht_dec.c \
  third_party/libopenjpeg/image.c \
  third_party/libopenjpeg/invert.c \
  third_party/libopenjpeg/j2k.c \
  third_party/libopenjpeg/jp2.c \
  third_party/libopenjpeg/mct.c \
  third_party/libopenjpeg/mqc.c \
  third_party/libopenjpeg/openjpeg.c \
  third_party/libopenjpeg/pi.c \
  third_party/libopenjpeg/sparse_array.c \
  third_party/libopenjpeg/t1.c \
  third_party/libopenjpeg/t2.c \
  third_party/libopenjpeg/tcd.c \
  third_party/libopenjpeg/tgt.c \
  third_party/libopenjpeg/thread.c

PDFIUM_GROUP_04_COMPILER := $(CC)
PDFIUM_GROUP_04_DEFINES := '-DNDEBUG' '-DNVALGRIND' '-DDYNAMIC_ANNOTATIONS_ENABLED=0' '-DZLIB_IMPLEMENTATION'
PDFIUM_GROUP_04_INCLUDES := '-I$(PDFIUM_SOURCE)' '-I$(PDFIUM_SOURCE)/third_party/zlib'
PDFIUM_GROUP_04_SOURCES := \
  third_party/zlib/adler32.c \
  third_party/zlib/compress.c \
  third_party/zlib/cpu_features.c \
  third_party/zlib/crc32.c \
  third_party/zlib/deflate.c \
  third_party/zlib/gzclose.c \
  third_party/zlib/gzlib.c \
  third_party/zlib/gzread.c \
  third_party/zlib/gzwrite.c \
  third_party/zlib/infback.c \
  third_party/zlib/inffast.c \
  third_party/zlib/inflate.c \
  third_party/zlib/inftrees.c \
  third_party/zlib/trees.c \
  third_party/zlib/uncompr.c \
  third_party/zlib/zutil.c

PDFIUM_GROUP_05_COMPILER := $(CC)
PDFIUM_GROUP_05_DEFINES := '-DNO_GETENV' '-DNO_PUTENV' '-DBITS_IN_JSAMPLE=12' '-D__STDC_CONSTANT_MACROS' '-D__STDC_FORMAT_MACROS' '-D_FORTIFY_SOURCE=2' '-DNDEBUG' '-DNVALGRIND' '-DDYNAMIC_ANNOTATIONS_ENABLED=0' '-DMANGLE_JPEG_NAMES'
PDFIUM_GROUP_05_INCLUDES := '-I$(PDFIUM_SOURCE)' '-I$(PDFIUM_SOURCE)/third_party/libjpeg_turbo/src'
PDFIUM_GROUP_05_SOURCES := \
  third_party/libjpeg_turbo/src/jcapistd.c \
  third_party/libjpeg_turbo/src/jccoefct.c \
  third_party/libjpeg_turbo/src/jccolor.c \
  third_party/libjpeg_turbo/src/jcdctmgr.c \
  third_party/libjpeg_turbo/src/jcdiffct.c \
  third_party/libjpeg_turbo/src/jclossls.c \
  third_party/libjpeg_turbo/src/jcmainct.c \
  third_party/libjpeg_turbo/src/jcprepct.c \
  third_party/libjpeg_turbo/src/jcsample.c \
  third_party/libjpeg_turbo/src/jdapistd.c \
  third_party/libjpeg_turbo/src/jdcoefct.c \
  third_party/libjpeg_turbo/src/jdcolor.c \
  third_party/libjpeg_turbo/src/jddctmgr.c \
  third_party/libjpeg_turbo/src/jddiffct.c \
  third_party/libjpeg_turbo/src/jdlossls.c \
  third_party/libjpeg_turbo/src/jdmainct.c \
  third_party/libjpeg_turbo/src/jdmerge.c \
  third_party/libjpeg_turbo/src/jdpostct.c \
  third_party/libjpeg_turbo/src/jdsample.c \
  third_party/libjpeg_turbo/src/jfdctfst.c \
  third_party/libjpeg_turbo/src/jfdctint.c \
  third_party/libjpeg_turbo/src/jidctflt.c \
  third_party/libjpeg_turbo/src/jidctfst.c \
  third_party/libjpeg_turbo/src/jidctint.c \
  third_party/libjpeg_turbo/src/jidctred.c \
  third_party/libjpeg_turbo/src/jquant1.c \
  third_party/libjpeg_turbo/src/jquant2.c \
  third_party/libjpeg_turbo/src/jutils.c

PDFIUM_GROUP_06_COMPILER := $(CC)
PDFIUM_GROUP_06_DEFINES := '-DNO_GETENV' '-DNO_PUTENV' '-DBITS_IN_JSAMPLE=16' '-D__STDC_CONSTANT_MACROS' '-D__STDC_FORMAT_MACROS' '-D_FORTIFY_SOURCE=2' '-DNDEBUG' '-DNVALGRIND' '-DDYNAMIC_ANNOTATIONS_ENABLED=0' '-DMANGLE_JPEG_NAMES'
PDFIUM_GROUP_06_INCLUDES := '-I$(PDFIUM_SOURCE)' '-I$(PDFIUM_SOURCE)/third_party/libjpeg_turbo/src'
PDFIUM_GROUP_06_SOURCES := \
  third_party/libjpeg_turbo/src/jcapistd.c \
  third_party/libjpeg_turbo/src/jccolor.c \
  third_party/libjpeg_turbo/src/jcdiffct.c \
  third_party/libjpeg_turbo/src/jclossls.c \
  third_party/libjpeg_turbo/src/jcmainct.c \
  third_party/libjpeg_turbo/src/jcprepct.c \
  third_party/libjpeg_turbo/src/jcsample.c \
  third_party/libjpeg_turbo/src/jdapistd.c \
  third_party/libjpeg_turbo/src/jdcolor.c \
  third_party/libjpeg_turbo/src/jddiffct.c \
  third_party/libjpeg_turbo/src/jdlossls.c \
  third_party/libjpeg_turbo/src/jdmainct.c \
  third_party/libjpeg_turbo/src/jdpostct.c \
  third_party/libjpeg_turbo/src/jdsample.c \
  third_party/libjpeg_turbo/src/jutils.c

PDFIUM_GROUP_07_COMPILER := $(CC)
PDFIUM_GROUP_07_DEFINES := '-DNO_GETENV' '-DNO_PUTENV' '-D__STDC_CONSTANT_MACROS' '-D__STDC_FORMAT_MACROS' '-D_FORTIFY_SOURCE=2' '-DNDEBUG' '-DNVALGRIND' '-DDYNAMIC_ANNOTATIONS_ENABLED=0' '-DMANGLE_JPEG_NAMES'
PDFIUM_GROUP_07_INCLUDES := '-I$(PDFIUM_SOURCE)' '-I$(PDFIUM_SOURCE)/third_party/libjpeg_turbo/src'
PDFIUM_GROUP_07_SOURCES := \
  third_party/libjpeg_turbo/src/jcapimin.c \
  third_party/libjpeg_turbo/src/jcapistd.c \
  third_party/libjpeg_turbo/src/jccoefct.c \
  third_party/libjpeg_turbo/src/jccolor.c \
  third_party/libjpeg_turbo/src/jcdctmgr.c \
  third_party/libjpeg_turbo/src/jcdiffct.c \
  third_party/libjpeg_turbo/src/jchuff.c \
  third_party/libjpeg_turbo/src/jcicc.c \
  third_party/libjpeg_turbo/src/jcinit.c \
  third_party/libjpeg_turbo/src/jclhuff.c \
  third_party/libjpeg_turbo/src/jclossls.c \
  third_party/libjpeg_turbo/src/jcmainct.c \
  third_party/libjpeg_turbo/src/jcmarker.c \
  third_party/libjpeg_turbo/src/jcmaster.c \
  third_party/libjpeg_turbo/src/jcomapi.c \
  third_party/libjpeg_turbo/src/jcparam.c \
  third_party/libjpeg_turbo/src/jcphuff.c \
  third_party/libjpeg_turbo/src/jcprepct.c \
  third_party/libjpeg_turbo/src/jcsample.c \
  third_party/libjpeg_turbo/src/jctrans.c \
  third_party/libjpeg_turbo/src/jdapimin.c \
  third_party/libjpeg_turbo/src/jdapistd.c \
  third_party/libjpeg_turbo/src/jdatadst.c \
  third_party/libjpeg_turbo/src/jdatasrc.c \
  third_party/libjpeg_turbo/src/jdcoefct.c \
  third_party/libjpeg_turbo/src/jdcolor.c \
  third_party/libjpeg_turbo/src/jddctmgr.c \
  third_party/libjpeg_turbo/src/jddiffct.c \
  third_party/libjpeg_turbo/src/jdhuff.c \
  third_party/libjpeg_turbo/src/jdicc.c \
  third_party/libjpeg_turbo/src/jdinput.c \
  third_party/libjpeg_turbo/src/jdlhuff.c \
  third_party/libjpeg_turbo/src/jdlossls.c \
  third_party/libjpeg_turbo/src/jdmainct.c \
  third_party/libjpeg_turbo/src/jdmarker.c \
  third_party/libjpeg_turbo/src/jdmaster.c \
  third_party/libjpeg_turbo/src/jdmerge.c \
  third_party/libjpeg_turbo/src/jdphuff.c \
  third_party/libjpeg_turbo/src/jdpostct.c \
  third_party/libjpeg_turbo/src/jdsample.c \
  third_party/libjpeg_turbo/src/jdtrans.c \
  third_party/libjpeg_turbo/src/jerror.c \
  third_party/libjpeg_turbo/src/jfdctflt.c \
  third_party/libjpeg_turbo/src/jfdctfst.c \
  third_party/libjpeg_turbo/src/jfdctint.c \
  third_party/libjpeg_turbo/src/jidctflt.c \
  third_party/libjpeg_turbo/src/jidctfst.c \
  third_party/libjpeg_turbo/src/jidctint.c \
  third_party/libjpeg_turbo/src/jidctred.c \
  third_party/libjpeg_turbo/src/jmemmgr.c \
  third_party/libjpeg_turbo/src/jmemnobs.c \
  third_party/libjpeg_turbo/src/jpeg_nbits.c \
  third_party/libjpeg_turbo/src/jquant1.c \
  third_party/libjpeg_turbo/src/jquant2.c \
  third_party/libjpeg_turbo/src/jutils.c

PDFIUM_GROUP_08_COMPILER := $(CC)
PDFIUM_GROUP_08_DEFINES := '-D__STDC_CONSTANT_MACROS' '-D__STDC_FORMAT_MACROS' '-D_FORTIFY_SOURCE=2' '-DNDEBUG' '-DNVALGRIND' '-DDYNAMIC_ANNOTATIONS_ENABLED=0'
PDFIUM_GROUP_08_INCLUDES := '-I$(PDFIUM_SOURCE)' '-I$(PDFIUM_SOURCE)/third_party/brotli/include'
PDFIUM_GROUP_08_SOURCES := \
  third_party/brotli/common/constants.c \
  third_party/brotli/common/context.c \
  third_party/brotli/common/dictionary.c \
  third_party/brotli/common/platform.c \
  third_party/brotli/common/shared_dictionary.c \
  third_party/brotli/common/transform.c

PDFIUM_GROUP_09_COMPILER := $(CC)
PDFIUM_GROUP_09_DEFINES := '-D__STDC_CONSTANT_MACROS' '-D__STDC_FORMAT_MACROS' '-D_FORTIFY_SOURCE=2' '-DNDEBUG' '-DNVALGRIND' '-DDYNAMIC_ANNOTATIONS_ENABLED=0' '-DAFDKO_VERSION_STRING="hyper-internal"'
PDFIUM_GROUP_09_INCLUDES := '-I$(PDFIUM_SOURCE)' '-I$(PDFIUM_SOURCE)/third_party/afdko/shared/include' '-I$(PDFIUM_SOURCE)/third_party/afdko/shared' '-I$(PDFIUM_SOURCE)/third_party/afdko/shared/cffwrite' '-I$(PDFIUM_SOURCE)/third_party/afdko/shared/absfont' '-I$(PDFIUM_SOURCE)/third_party/afdko/shared/support' '-I$(PDFIUM_SOURCE)/third_party/afdko/shared/resource'
PDFIUM_GROUP_09_SOURCES := \
  third_party/afdko/shared/cffread.c \
  third_party/afdko/shared/ctutil.c \
  third_party/afdko/shared/da.c \
  third_party/afdko/shared/dynarr.c \
  third_party/afdko/shared/sha1.c \
  third_party/afdko/shared/smem.c \
  third_party/afdko/shared/support/except.c \
  third_party/afdko/shared/support/fixed.c

PDFIUM_GROUP_10_COMPILER := $(CC)
PDFIUM_GROUP_10_DEFINES := '-D__STDC_CONSTANT_MACROS' '-D__STDC_FORMAT_MACROS' '-D_FORTIFY_SOURCE=2' '-DNDEBUG' '-DNVALGRIND' '-DDYNAMIC_ANNOTATIONS_ENABLED=0' '-DHAVE_LIBPNG=0' '-DHAVE_LIBJPEG=0' '-DHAVE_LIBTIFF=0' '-DHAVE_LIBGIF=0' '-DHAVE_LIBUNGIF=0' '-DHAVE_LIBJP2K=0' '-DHAVE_LIBWEBP=0' '-DHAVE_LIBWEBP_ANIM=0' '-DHAVE_LIBZ=0' '-DNO_CONSOLE_IO' '-DHAVE_FMEMOPEN=1'
PDFIUM_GROUP_10_INCLUDES := '-I$(PDFIUM_SOURCE)' '-I$(PDFIUM_SOURCE)/third_party/leptonica/src'
PDFIUM_GROUP_10_SOURCES := \
  third_party/leptonica/src/adaptmap.c \
  third_party/leptonica/src/affine.c \
  third_party/leptonica/src/affinecompose.c \
  third_party/leptonica/src/arrayaccess.c \
  third_party/leptonica/src/bardecode.c \
  third_party/leptonica/src/baseline.c \
  third_party/leptonica/src/bbuffer.c \
  third_party/leptonica/src/bilateral.c \
  third_party/leptonica/src/bilinear.c \
  third_party/leptonica/src/binarize.c \
  third_party/leptonica/src/binexpand.c \
  third_party/leptonica/src/binreduce.c \
  third_party/leptonica/src/blend.c \
  third_party/leptonica/src/bmf.c \
  third_party/leptonica/src/bmpio.c \
  third_party/leptonica/src/bmpiostub.c \
  third_party/leptonica/src/bootnumgen1.c \
  third_party/leptonica/src/bootnumgen2.c \
  third_party/leptonica/src/bootnumgen3.c \
  third_party/leptonica/src/bootnumgen4.c \
  third_party/leptonica/src/boxbasic.c \
  third_party/leptonica/src/boxfunc1.c \
  third_party/leptonica/src/boxfunc2.c \
  third_party/leptonica/src/boxfunc3.c \
  third_party/leptonica/src/boxfunc4.c \
  third_party/leptonica/src/boxfunc5.c \
  third_party/leptonica/src/bytearray.c \
  third_party/leptonica/src/ccbord.c \
  third_party/leptonica/src/ccthin.c \
  third_party/leptonica/src/checkerboard.c \
  third_party/leptonica/src/classapp.c \
  third_party/leptonica/src/colorcontent.c \
  third_party/leptonica/src/colorfill.c \
  third_party/leptonica/src/coloring.c \
  third_party/leptonica/src/colormap.c \
  third_party/leptonica/src/colormorph.c \
  third_party/leptonica/src/colorquant1.c \
  third_party/leptonica/src/colorquant2.c \
  third_party/leptonica/src/colorseg.c \
  third_party/leptonica/src/colorspace.c \
  third_party/leptonica/src/compare.c \
  third_party/leptonica/src/conncomp.c \
  third_party/leptonica/src/convertfiles.c \
  third_party/leptonica/src/convolve.c \
  third_party/leptonica/src/correlscore.c \
  third_party/leptonica/src/dewarp1.c \
  third_party/leptonica/src/dewarp2.c \
  third_party/leptonica/src/dewarp3.c \
  third_party/leptonica/src/dewarp4.c \
  third_party/leptonica/src/dnabasic.c \
  third_party/leptonica/src/dnafunc1.c \
  third_party/leptonica/src/dnahash.c \
  third_party/leptonica/src/dwacomb.2.c \
  third_party/leptonica/src/dwacomblow.2.c \
  third_party/leptonica/src/edge.c \
  third_party/leptonica/src/encoding.c \
  third_party/leptonica/src/enhance.c \
  third_party/leptonica/src/fhmtauto.c \
  third_party/leptonica/src/fhmtgen.1.c \
  third_party/leptonica/src/fhmtgenlow.1.c \
  third_party/leptonica/src/finditalic.c \
  third_party/leptonica/src/flipdetect.c \
  third_party/leptonica/src/fmorphauto.c \
  third_party/leptonica/src/fmorphgen.1.c \
  third_party/leptonica/src/fmorphgenlow.1.c \
  third_party/leptonica/src/fpix1.c \
  third_party/leptonica/src/fpix2.c \
  third_party/leptonica/src/gifio.c \
  third_party/leptonica/src/gifiostub.c \
  third_party/leptonica/src/gplot.c \
  third_party/leptonica/src/graphics.c \
  third_party/leptonica/src/graymorph.c \
  third_party/leptonica/src/grayquant.c \
  third_party/leptonica/src/hashmap.c \
  third_party/leptonica/src/heap.c \
  third_party/leptonica/src/jbclass.c \
  third_party/leptonica/src/jp2kheader.c \
  third_party/leptonica/src/jp2kheaderstub.c \
  third_party/leptonica/src/jp2kio.c \
  third_party/leptonica/src/jp2kiostub.c \
  third_party/leptonica/src/jpegio.c \
  third_party/leptonica/src/jpegiostub.c \
  third_party/leptonica/src/kernel.c \
  third_party/leptonica/src/libversions.c \
  third_party/leptonica/src/list.c \
  third_party/leptonica/src/map.c \
  third_party/leptonica/src/maze.c \
  third_party/leptonica/src/morph.c \
  third_party/leptonica/src/morphapp.c \
  third_party/leptonica/src/morphdwa.c \
  third_party/leptonica/src/morphseq.c \
  third_party/leptonica/src/numabasic.c \
  third_party/leptonica/src/numafunc1.c \
  third_party/leptonica/src/numafunc2.c \
  third_party/leptonica/src/pageseg.c \
  third_party/leptonica/src/paintcmap.c \
  third_party/leptonica/src/parseprotos.c \
  third_party/leptonica/src/partify.c \
  third_party/leptonica/src/partition.c \
  third_party/leptonica/src/pdfapp.c \
  third_party/leptonica/src/pdfappstub.c \
  third_party/leptonica/src/pdfio1.c \
  third_party/leptonica/src/pdfio1stub.c \
  third_party/leptonica/src/pdfio2.c \
  third_party/leptonica/src/pdfio2stub.c \
  third_party/leptonica/src/pix1.c \
  third_party/leptonica/src/pix2.c \
  third_party/leptonica/src/pix3.c \
  third_party/leptonica/src/pix4.c \
  third_party/leptonica/src/pix5.c \
  third_party/leptonica/src/pixabasic.c \
  third_party/leptonica/src/pixacc.c \
  third_party/leptonica/src/pixafunc1.c \
  third_party/leptonica/src/pixafunc2.c \
  third_party/leptonica/src/pixalloc.c \
  third_party/leptonica/src/pixarith.c \
  third_party/leptonica/src/pixcomp.c \
  third_party/leptonica/src/pixconv.c \
  third_party/leptonica/src/pixlabel.c \
  third_party/leptonica/src/pixtiling.c \
  third_party/leptonica/src/pngio.c \
  third_party/leptonica/src/pngiostub.c \
  third_party/leptonica/src/pnmio.c \
  third_party/leptonica/src/pnmiostub.c \
  third_party/leptonica/src/projective.c \
  third_party/leptonica/src/psio1.c \
  third_party/leptonica/src/psio1stub.c \
  third_party/leptonica/src/psio2.c \
  third_party/leptonica/src/psio2stub.c \
  third_party/leptonica/src/ptabasic.c \
  third_party/leptonica/src/ptafunc1.c \
  third_party/leptonica/src/ptafunc2.c \
  third_party/leptonica/src/ptra.c \
  third_party/leptonica/src/quadtree.c \
  third_party/leptonica/src/queue.c \
  third_party/leptonica/src/rank.c \
  third_party/leptonica/src/rbtree.c \
  third_party/leptonica/src/readbarcode.c \
  third_party/leptonica/src/readfile.c \
  third_party/leptonica/src/recogbasic.c \
  third_party/leptonica/src/recogdid.c \
  third_party/leptonica/src/recogident.c \
  third_party/leptonica/src/recogtrain.c \
  third_party/leptonica/src/regutils.c \
  third_party/leptonica/src/renderpdf.c \
  third_party/leptonica/src/rop.c \
  third_party/leptonica/src/roplow.c \
  third_party/leptonica/src/rotate.c \
  third_party/leptonica/src/rotateam.c \
  third_party/leptonica/src/rotateorth.c \
  third_party/leptonica/src/rotateshear.c \
  third_party/leptonica/src/runlength.c \
  third_party/leptonica/src/sarray1.c \
  third_party/leptonica/src/sarray2.c \
  third_party/leptonica/src/scale1.c \
  third_party/leptonica/src/scale2.c \
  third_party/leptonica/src/seedfill.c \
  third_party/leptonica/src/sel1.c \
  third_party/leptonica/src/sel2.c \
  third_party/leptonica/src/selgen.c \
  third_party/leptonica/src/shear.c \
  third_party/leptonica/src/skew.c \
  third_party/leptonica/src/spixio.c \
  third_party/leptonica/src/stack.c \
  third_party/leptonica/src/stringcode.c \
  third_party/leptonica/src/strokes.c \
  third_party/leptonica/src/sudoku.c \
  third_party/leptonica/src/textops.c \
  third_party/leptonica/src/tiffio.c \
  third_party/leptonica/src/tiffiostub.c \
  third_party/leptonica/src/utils1.c \
  third_party/leptonica/src/utils2.c \
  third_party/leptonica/src/warper.c \
  third_party/leptonica/src/watershed.c \
  third_party/leptonica/src/webpanimio.c \
  third_party/leptonica/src/webpanimiostub.c \
  third_party/leptonica/src/webpio.c \
  third_party/leptonica/src/webpiostub.c \
  third_party/leptonica/src/writefile.c \
  third_party/leptonica/src/zlibmem.c \
  third_party/leptonica/src/zlibmemstub.c

PDFIUM_GROUP_11_COMPILER := $(CC)
PDFIUM_GROUP_11_DEFINES := '-D__STDC_CONSTANT_MACROS' '-D__STDC_FORMAT_MACROS' '-D_FORTIFY_SOURCE=2' '-DNDEBUG' '-DNVALGRIND' '-DDYNAMIC_ANNOTATIONS_ENABLED=0' '-DOPJ_STATIC' '-DPDF_ENABLE_BROTLI' '-DPDF_USE_AGG' '-DFT_CONFIG_MODULES_H="freetype-custom-config/ftmodule.h"' '-DFT_CONFIG_OPTIONS_H="freetype-custom-config/ftoption.h"' '-DU_USING_ICU_NAMESPACE=0' '-DU_ENABLE_DYLOAD=0' '-DUSE_CHROMIUM_ICU=1' '-DU_ENABLE_TRACING=1' '-DU_ENABLE_RESOURCE_TRACING=0' '-DU_STATIC_IMPLEMENTATION' '-DICU_UTIL_DATA_IMPL=ICU_UTIL_DATA_FILE' '-DUSE_LIBJPEG_TURBO=1' '-DMANGLE_JPEG_NAMES'
PDFIUM_GROUP_11_INCLUDES := '-I$(PDFIUM_SOURCE)' '-I$(PDFIUM_SOURCE)/third_party/freetype/include' '-I$(PDFIUM_SOURCE)/third_party/freetype/src/include' '-I$(PDFIUM_SOURCE)/third_party/abseil-cpp' '-I$(PDFIUM_SOURCE)/third_party/icu/source/common' '-I$(PDFIUM_SOURCE)/third_party/icu/source/i18n' '-I$(PDFIUM_SOURCE)/third_party/zlib' '-I$(PDFIUM_SOURCE)/third_party/brotli/include' '-I$(PDFIUM_SOURCE)/third_party/libjpeg_turbo/src'
PDFIUM_GROUP_11_SOURCES := \
  core/fxcodec/jpeg/jpeg_common.c

PDFIUM_GROUP_12_COMPILER := $(CXX)
PDFIUM_GROUP_12_DEFINES := '-DHAVE_OT' '-DHAVE_ICU' '-DHAVE_ICU_BUILTIN' '-DHB_NO_MMAP' '-DHB_NO_RESOURCE_FORK' '-DHB_NO_PAINT=' '-DHB_NO_SUBSET_LAYOUT' '-DHB_NO_FALLBACK_SHAPE' '-DHB_NO_UCD' '-DHB_NO_WIN1256' '-DU_DISABLE_VERSION_SUFFIX=0' '-DHB_NO_BUFFER_VERIFY' '-DHB_NO_DRAW' '-DHB_CONFIG_OVERRIDE_LAST_H="pdfium-config-override.h"' '-DHB_NO_BORING_EXPANSION' '-DHB_NO_AVAR2' '-DHB_NO_PRAGMA_GCC_DIAGNOSTIC_ERROR' '-DHB_NO_PRAGMA_GCC_DIAGNOSTIC_WARNING' '-DNDEBUG' '-DNVALGRIND' '-DDYNAMIC_ANNOTATIONS_ENABLED=0' '-DU_USING_ICU_NAMESPACE=0' '-DU_ENABLE_DYLOAD=0' '-DUSE_CHROMIUM_ICU=1' '-DU_ENABLE_TRACING=1' '-DU_ENABLE_RESOURCE_TRACING=0' '-DU_STATIC_IMPLEMENTATION' '-DICU_UTIL_DATA_IMPL=ICU_UTIL_DATA_FILE'
PDFIUM_GROUP_12_INCLUDES := '-I$(PDFIUM_SOURCE)' '-I$(PDFIUM_SOURCE)/third_party/harfbuzz/src/src' '-I$(PDFIUM_SOURCE)/third_party/harfbuzz' '-I$(PDFIUM_SOURCE)/third_party/icu/source/common' '-I$(PDFIUM_SOURCE)/third_party/icu/source/i18n'
PDFIUM_GROUP_12_SOURCES := \
  third_party/harfbuzz/src/src/OT/Var/VARC/VARC.cc \
  third_party/harfbuzz/src/src/graph/gsubgpos-context.cc \
  third_party/harfbuzz/src/src/hb-aat-layout.cc \
  third_party/harfbuzz/src/src/hb-aat-map.cc \
  third_party/harfbuzz/src/src/hb-blob.cc \
  third_party/harfbuzz/src/src/hb-buffer-serialize.cc \
  third_party/harfbuzz/src/src/hb-buffer-verify.cc \
  third_party/harfbuzz/src/src/hb-buffer.cc \
  third_party/harfbuzz/src/src/hb-common.cc \
  third_party/harfbuzz/src/src/hb-draw.cc \
  third_party/harfbuzz/src/src/hb-face-builder.cc \
  third_party/harfbuzz/src/src/hb-face.cc \
  third_party/harfbuzz/src/src/hb-font.cc \
  third_party/harfbuzz/src/src/hb-harfrust.cc \
  third_party/harfbuzz/src/src/hb-icu.cc \
  third_party/harfbuzz/src/src/hb-kbts.cc \
  third_party/harfbuzz/src/src/hb-map.cc \
  third_party/harfbuzz/src/src/hb-number.cc \
  third_party/harfbuzz/src/src/hb-ot-cff1-table.cc \
  third_party/harfbuzz/src/src/hb-ot-cff2-table.cc \
  third_party/harfbuzz/src/src/hb-ot-color.cc \
  third_party/harfbuzz/src/src/hb-ot-face.cc \
  third_party/harfbuzz/src/src/hb-ot-font.cc \
  third_party/harfbuzz/src/src/hb-ot-layout.cc \
  third_party/harfbuzz/src/src/hb-ot-map.cc \
  third_party/harfbuzz/src/src/hb-ot-math.cc \
  third_party/harfbuzz/src/src/hb-ot-meta.cc \
  third_party/harfbuzz/src/src/hb-ot-metrics.cc \
  third_party/harfbuzz/src/src/hb-ot-name.cc \
  third_party/harfbuzz/src/src/hb-ot-shape-fallback.cc \
  third_party/harfbuzz/src/src/hb-ot-shape-normalize.cc \
  third_party/harfbuzz/src/src/hb-ot-shape.cc \
  third_party/harfbuzz/src/src/hb-ot-shaper-arabic.cc \
  third_party/harfbuzz/src/src/hb-ot-shaper-default.cc \
  third_party/harfbuzz/src/src/hb-ot-shaper-hangul.cc \
  third_party/harfbuzz/src/src/hb-ot-shaper-hebrew.cc \
  third_party/harfbuzz/src/src/hb-ot-shaper-indic-table.cc \
  third_party/harfbuzz/src/src/hb-ot-shaper-indic.cc \
  third_party/harfbuzz/src/src/hb-ot-shaper-khmer.cc \
  third_party/harfbuzz/src/src/hb-ot-shaper-myanmar.cc \
  third_party/harfbuzz/src/src/hb-ot-shaper-syllabic.cc \
  third_party/harfbuzz/src/src/hb-ot-shaper-thai.cc \
  third_party/harfbuzz/src/src/hb-ot-shaper-use.cc \
  third_party/harfbuzz/src/src/hb-ot-shaper-vowel-constraints.cc \
  third_party/harfbuzz/src/src/hb-ot-tag.cc \
  third_party/harfbuzz/src/src/hb-ot-var.cc \
  third_party/harfbuzz/src/src/hb-set.cc \
  third_party/harfbuzz/src/src/hb-shape-plan.cc \
  third_party/harfbuzz/src/src/hb-shape.cc \
  third_party/harfbuzz/src/src/hb-shaper.cc \
  third_party/harfbuzz/src/src/hb-static.cc \
  third_party/harfbuzz/src/src/hb-subset-cff-common.cc \
  third_party/harfbuzz/src/src/hb-subset-cff1.cc \
  third_party/harfbuzz/src/src/hb-subset-cff2.cc \
  third_party/harfbuzz/src/src/hb-subset-input.cc \
  third_party/harfbuzz/src/src/hb-subset-instancer-iup.cc \
  third_party/harfbuzz/src/src/hb-subset-instancer-solver.cc \
  third_party/harfbuzz/src/src/hb-subset-plan-layout.cc \
  third_party/harfbuzz/src/src/hb-subset-plan-var.cc \
  third_party/harfbuzz/src/src/hb-subset-plan.cc \
  third_party/harfbuzz/src/src/hb-subset-serialize.cc \
  third_party/harfbuzz/src/src/hb-subset-table-cff.cc \
  third_party/harfbuzz/src/src/hb-subset-table-color.cc \
  third_party/harfbuzz/src/src/hb-subset-table-layout.cc \
  third_party/harfbuzz/src/src/hb-subset-table-other.cc \
  third_party/harfbuzz/src/src/hb-subset-table-var.cc \
  third_party/harfbuzz/src/src/hb-subset.cc \
  third_party/harfbuzz/src/src/hb-ucd.cc \
  third_party/harfbuzz/src/src/hb-unicode.cc

PDFIUM_GROUP_13_COMPILER := $(CXX)
PDFIUM_GROUP_13_DEFINES := '-DNDEBUG' '-DNVALGRIND' '-DDYNAMIC_ANNOTATIONS_ENABLED=0' '-DABSL_ALLOCATOR_NOTHROW=1'
PDFIUM_GROUP_13_INCLUDES := '-I$(PDFIUM_SOURCE)' '-I$(PDFIUM_SOURCE)/third_party/abseil-cpp'
PDFIUM_GROUP_13_SOURCES := \
  third_party/abseil-cpp/absl/base/casts.cc \
  third_party/abseil-cpp/absl/base/internal/cpu_detect.cc \
  third_party/abseil-cpp/absl/base/internal/cycleclock.cc \
  third_party/abseil-cpp/absl/base/internal/hardening.cc \
  third_party/abseil-cpp/absl/base/internal/low_level_alloc.cc \
  third_party/abseil-cpp/absl/base/internal/raw_logging.cc \
  third_party/abseil-cpp/absl/base/internal/spinlock.cc \
  third_party/abseil-cpp/absl/base/internal/spinlock_wait.cc \
  third_party/abseil-cpp/absl/base/internal/strerror.cc \
  third_party/abseil-cpp/absl/base/internal/sysinfo.cc \
  third_party/abseil-cpp/absl/base/internal/thread_identity.cc \
  third_party/abseil-cpp/absl/base/internal/tracing.cc \
  third_party/abseil-cpp/absl/base/internal/unscaledcycleclock.cc \
  third_party/abseil-cpp/absl/base/log_severity.cc \
  third_party/abseil-cpp/absl/base/throw_delegate.cc \
  third_party/abseil-cpp/absl/container/internal/hashtablez_sampler.cc \
  third_party/abseil-cpp/absl/container/internal/hashtablez_sampler_force_weak_definition.cc \
  third_party/abseil-cpp/absl/container/internal/raw_hash_set.cc \
  third_party/abseil-cpp/absl/crc/crc32c.cc \
  third_party/abseil-cpp/absl/crc/internal/crc.cc \
  third_party/abseil-cpp/absl/crc/internal/crc_cord_state.cc \
  third_party/abseil-cpp/absl/crc/internal/crc_memcpy_fallback.cc \
  third_party/abseil-cpp/absl/crc/internal/crc_memcpy_x86_arm_combined.cc \
  third_party/abseil-cpp/absl/crc/internal/crc_non_temporal_memcpy.cc \
  third_party/abseil-cpp/absl/crc/internal/crc_x86_arm_combined.cc \
  third_party/abseil-cpp/absl/debugging/failure_signal_handler.cc \
  third_party/abseil-cpp/absl/debugging/internal/address_is_readable.cc \
  third_party/abseil-cpp/absl/debugging/internal/decode_rust_punycode.cc \
  third_party/abseil-cpp/absl/debugging/internal/demangle.cc \
  third_party/abseil-cpp/absl/debugging/internal/demangle_rust.cc \
  third_party/abseil-cpp/absl/debugging/internal/elf_mem_image.cc \
  third_party/abseil-cpp/absl/debugging/internal/examine_stack.cc \
  third_party/abseil-cpp/absl/debugging/internal/utf8_for_code_point.cc \
  third_party/abseil-cpp/absl/debugging/internal/vdso_support.cc \
  third_party/abseil-cpp/absl/debugging/leak_check.cc \
  third_party/abseil-cpp/absl/debugging/stacktrace.cc \
  third_party/abseil-cpp/absl/debugging/symbolize.cc \
  third_party/abseil-cpp/absl/hash/internal/city.cc \
  third_party/abseil-cpp/absl/hash/internal/hash.cc \
  third_party/abseil-cpp/absl/log/die_if_null.cc \
  third_party/abseil-cpp/absl/log/globals.cc \
  third_party/abseil-cpp/absl/log/initialize.cc \
  third_party/abseil-cpp/absl/log/internal/check_op.cc \
  third_party/abseil-cpp/absl/log/internal/conditions.cc \
  third_party/abseil-cpp/absl/log/internal/fnmatch.cc \
  third_party/abseil-cpp/absl/log/internal/globals.cc \
  third_party/abseil-cpp/absl/log/internal/log_format.cc \
  third_party/abseil-cpp/absl/log/internal/log_message.cc \
  third_party/abseil-cpp/absl/log/internal/log_sink_set.cc \
  third_party/abseil-cpp/absl/log/internal/nullguard.cc \
  third_party/abseil-cpp/absl/log/internal/proto.cc \
  third_party/abseil-cpp/absl/log/internal/structured_proto.cc \
  third_party/abseil-cpp/absl/log/internal/vlog_config.cc \
  third_party/abseil-cpp/absl/log/log_entry.cc \
  third_party/abseil-cpp/absl/log/log_sink.cc \
  third_party/abseil-cpp/absl/numeric/int128.cc \
  third_party/abseil-cpp/absl/profiling/internal/exponential_biased.cc \
  third_party/abseil-cpp/absl/random/discrete_distribution.cc \
  third_party/abseil-cpp/absl/random/gaussian_distribution.cc \
  third_party/abseil-cpp/absl/random/internal/entropy_pool.cc \
  third_party/abseil-cpp/absl/random/internal/randen.cc \
  third_party/abseil-cpp/absl/random/internal/randen_detect.cc \
  third_party/abseil-cpp/absl/random/internal/randen_hwaes.cc \
  third_party/abseil-cpp/absl/random/internal/randen_round_keys.cc \
  third_party/abseil-cpp/absl/random/internal/randen_slow.cc \
  third_party/abseil-cpp/absl/random/internal/seed_material.cc \
  third_party/abseil-cpp/absl/random/seed_gen_exception.cc \
  third_party/abseil-cpp/absl/random/seed_sequences.cc \
  third_party/abseil-cpp/absl/status/internal/status_internal.cc \
  third_party/abseil-cpp/absl/status/status.cc \
  third_party/abseil-cpp/absl/status/status_builder.cc \
  third_party/abseil-cpp/absl/status/status_payload_printer.cc \
  third_party/abseil-cpp/absl/status/statusor.cc \
  third_party/abseil-cpp/absl/strings/ascii.cc \
  third_party/abseil-cpp/absl/strings/charconv.cc \
  third_party/abseil-cpp/absl/strings/cord.cc \
  third_party/abseil-cpp/absl/strings/cord_analysis.cc \
  third_party/abseil-cpp/absl/strings/escaping.cc \
  third_party/abseil-cpp/absl/strings/internal/charconv_bigint.cc \
  third_party/abseil-cpp/absl/strings/internal/charconv_parse.cc \
  third_party/abseil-cpp/absl/strings/internal/cord_internal.cc \
  third_party/abseil-cpp/absl/strings/internal/cord_rep_btree.cc \
  third_party/abseil-cpp/absl/strings/internal/cord_rep_btree_navigator.cc \
  third_party/abseil-cpp/absl/strings/internal/cord_rep_btree_reader.cc \
  third_party/abseil-cpp/absl/strings/internal/cord_rep_consume.cc \
  third_party/abseil-cpp/absl/strings/internal/cord_rep_crc.cc \
  third_party/abseil-cpp/absl/strings/internal/cordz_functions.cc \
  third_party/abseil-cpp/absl/strings/internal/cordz_handle.cc \
  third_party/abseil-cpp/absl/strings/internal/cordz_info.cc \
  third_party/abseil-cpp/absl/strings/internal/damerau_levenshtein_distance.cc \
  third_party/abseil-cpp/absl/strings/internal/escaping.cc \
  third_party/abseil-cpp/absl/strings/internal/memutil.cc \
  third_party/abseil-cpp/absl/strings/internal/ostringstream.cc \
  third_party/abseil-cpp/absl/strings/internal/str_format/arg.cc \
  third_party/abseil-cpp/absl/strings/internal/str_format/bind.cc \
  third_party/abseil-cpp/absl/strings/internal/str_format/extension.cc \
  third_party/abseil-cpp/absl/strings/internal/str_format/float_conversion.cc \
  third_party/abseil-cpp/absl/strings/internal/str_format/output.cc \
  third_party/abseil-cpp/absl/strings/internal/str_format/parser.cc \
  third_party/abseil-cpp/absl/strings/internal/stringify_sink.cc \
  third_party/abseil-cpp/absl/strings/internal/utf8.cc \
  third_party/abseil-cpp/absl/strings/match.cc \
  third_party/abseil-cpp/absl/strings/numbers.cc \
  third_party/abseil-cpp/absl/strings/str_cat.cc \
  third_party/abseil-cpp/absl/strings/str_replace.cc \
  third_party/abseil-cpp/absl/strings/str_split.cc \
  third_party/abseil-cpp/absl/strings/substitute.cc \
  third_party/abseil-cpp/absl/synchronization/barrier.cc \
  third_party/abseil-cpp/absl/synchronization/blocking_counter.cc \
  third_party/abseil-cpp/absl/synchronization/internal/create_thread_identity.cc \
  third_party/abseil-cpp/absl/synchronization/internal/futex_waiter.cc \
  third_party/abseil-cpp/absl/synchronization/internal/graphcycles.cc \
  third_party/abseil-cpp/absl/synchronization/internal/kernel_timeout.cc \
  third_party/abseil-cpp/absl/synchronization/internal/per_thread_sem.cc \
  third_party/abseil-cpp/absl/synchronization/internal/pthread_waiter.cc \
  third_party/abseil-cpp/absl/synchronization/internal/sem_waiter.cc \
  third_party/abseil-cpp/absl/synchronization/internal/stdcpp_waiter.cc \
  third_party/abseil-cpp/absl/synchronization/internal/waiter_base.cc \
  third_party/abseil-cpp/absl/synchronization/internal/win32_waiter.cc \
  third_party/abseil-cpp/absl/synchronization/mutex.cc \
  third_party/abseil-cpp/absl/synchronization/notification.cc \
  third_party/abseil-cpp/absl/time/civil_time.cc \
  third_party/abseil-cpp/absl/time/clock.cc \
  third_party/abseil-cpp/absl/time/clock_interface.cc \
  third_party/abseil-cpp/absl/time/duration.cc \
  third_party/abseil-cpp/absl/time/format.cc \
  third_party/abseil-cpp/absl/time/internal/cctz/src/civil_time_detail.cc \
  third_party/abseil-cpp/absl/time/time.cc \
  third_party/abseil-cpp/absl/types/source_location.cc

PDFIUM_GROUP_14_COMPILER := $(CXX)
PDFIUM_GROUP_14_DEFINES := '-DNDEBUG' '-DNVALGRIND' '-DDYNAMIC_ANNOTATIONS_ENABLED=0' '-DOPJ_STATIC' '-DPDF_ENABLE_BROTLI' '-DPDF_USE_AGG' '-DFT_CONFIG_MODULES_H="freetype-custom-config/ftmodule.h"' '-DFT_CONFIG_OPTIONS_H="freetype-custom-config/ftoption.h"' '-DU_USING_ICU_NAMESPACE=0' '-DU_ENABLE_DYLOAD=0' '-DUSE_CHROMIUM_ICU=1' '-DU_ENABLE_TRACING=1' '-DU_ENABLE_RESOURCE_TRACING=0' '-DU_STATIC_IMPLEMENTATION' '-DICU_UTIL_DATA_IMPL=ICU_UTIL_DATA_FILE'
PDFIUM_GROUP_14_INCLUDES := '-I$(PDFIUM_SOURCE)' '-I$(PDFIUM_SOURCE)/third_party/freetype/include' '-I$(PDFIUM_SOURCE)/third_party/freetype/src/include' '-I$(PDFIUM_SOURCE)/third_party/abseil-cpp' '-I$(PDFIUM_SOURCE)/third_party/icu/source/common' '-I$(PDFIUM_SOURCE)/third_party/icu/source/i18n'
PDFIUM_GROUP_14_SOURCES := \
  third_party/agg23/agg_curves.cpp \
  third_party/agg23/agg_path_storage.cpp \
  third_party/agg23/agg_rasterizer_scanline_aa.cpp \
  third_party/agg23/agg_vcgen_dash.cpp \
  third_party/agg23/agg_vcgen_stroke.cpp \
  third_party/libopenjpeg/opj_malloc.cc

PDFIUM_GROUP_15_COMPILER := $(CXX)
PDFIUM_GROUP_15_DEFINES := '-DU_COMMON_IMPLEMENTATION' '-DU_ICUDATAENTRY_IN_COMMON' '-DNDEBUG' '-DNVALGRIND' '-DDYNAMIC_ANNOTATIONS_ENABLED=0' '-DHAVE_DLOPEN=0' '-DUCONFIG_ONLY_HTML_CONVERSION=1' '-DUCONFIG_USE_ML_PHRASE_BREAKING=1' '-DUCONFIG_USE_WINDOWS_LCID_MAPPING_API=0' '-DU_CHARSET_IS_UTF8=1' '-DU_USING_ICU_NAMESPACE=0' '-DU_ENABLE_DYLOAD=0' '-DUSE_CHROMIUM_ICU=1' '-DU_ENABLE_TRACING=1' '-DU_ENABLE_RESOURCE_TRACING=0' '-DU_STATIC_IMPLEMENTATION' '-DICU_UTIL_DATA_IMPL=ICU_UTIL_DATA_FILE'
PDFIUM_GROUP_15_INCLUDES := '-I$(PDFIUM_SOURCE)' '-I$(PDFIUM_SOURCE)/third_party/icu/source/common' '-I$(PDFIUM_SOURCE)/third_party/icu/source/i18n'
PDFIUM_GROUP_15_SOURCES := \
  third_party/icu/source/common/appendable.cpp \
  third_party/icu/source/common/bmpset.cpp \
  third_party/icu/source/common/brkeng.cpp \
  third_party/icu/source/common/brkiter.cpp \
  third_party/icu/source/common/bytesinkutil.cpp \
  third_party/icu/source/common/bytestream.cpp \
  third_party/icu/source/common/bytestrie.cpp \
  third_party/icu/source/common/bytestriebuilder.cpp \
  third_party/icu/source/common/bytestrieiterator.cpp \
  third_party/icu/source/common/caniter.cpp \
  third_party/icu/source/common/characterproperties.cpp \
  third_party/icu/source/common/chariter.cpp \
  third_party/icu/source/common/charstr.cpp \
  third_party/icu/source/common/cmemory.cpp \
  third_party/icu/source/common/cstr.cpp \
  third_party/icu/source/common/cstring.cpp \
  third_party/icu/source/common/cwchar.cpp \
  third_party/icu/source/common/dictbe.cpp \
  third_party/icu/source/common/dictionarydata.cpp \
  third_party/icu/source/common/dtintrv.cpp \
  third_party/icu/source/common/edits.cpp \
  third_party/icu/source/common/emojiprops.cpp \
  third_party/icu/source/common/errorcode.cpp \
  third_party/icu/source/common/filteredbrk.cpp \
  third_party/icu/source/common/filterednormalizer2.cpp \
  third_party/icu/source/common/fixedstring.cpp \
  third_party/icu/source/common/icudataver.cpp \
  third_party/icu/source/common/icuplug.cpp \
  third_party/icu/source/common/loadednormalizer2impl.cpp \
  third_party/icu/source/common/localebuilder.cpp \
  third_party/icu/source/common/localematcher.cpp \
  third_party/icu/source/common/localeprioritylist.cpp \
  third_party/icu/source/common/locavailable.cpp \
  third_party/icu/source/common/locbased.cpp \
  third_party/icu/source/common/locdispnames.cpp \
  third_party/icu/source/common/locdistance.cpp \
  third_party/icu/source/common/locdspnm.cpp \
  third_party/icu/source/common/locid.cpp \
  third_party/icu/source/common/loclikely.cpp \
  third_party/icu/source/common/loclikelysubtags.cpp \
  third_party/icu/source/common/locmap.cpp \
  third_party/icu/source/common/locresdata.cpp \
  third_party/icu/source/common/locutil.cpp \
  third_party/icu/source/common/lsr.cpp \
  third_party/icu/source/common/lstmbe.cpp \
  third_party/icu/source/common/messagepattern.cpp \
  third_party/icu/source/common/mlbe.cpp \
  third_party/icu/source/common/normalizer2.cpp \
  third_party/icu/source/common/normalizer2impl.cpp \
  third_party/icu/source/common/normlzr.cpp \
  third_party/icu/source/common/parsepos.cpp \
  third_party/icu/source/common/patternprops.cpp \
  third_party/icu/source/common/pluralmap.cpp \
  third_party/icu/source/common/propname.cpp \
  third_party/icu/source/common/propsvec.cpp \
  third_party/icu/source/common/punycode.cpp \
  third_party/icu/source/common/putil.cpp \
  third_party/icu/source/common/rbbi.cpp \
  third_party/icu/source/common/rbbi_cache.cpp \
  third_party/icu/source/common/rbbidata.cpp \
  third_party/icu/source/common/rbbinode.cpp \
  third_party/icu/source/common/rbbirb.cpp \
  third_party/icu/source/common/rbbiscan.cpp \
  third_party/icu/source/common/rbbisetb.cpp \
  third_party/icu/source/common/rbbistbl.cpp \
  third_party/icu/source/common/rbbitblb.cpp \
  third_party/icu/source/common/resbund.cpp \
  third_party/icu/source/common/resbund_cnv.cpp \
  third_party/icu/source/common/resource.cpp \
  third_party/icu/source/common/restrace.cpp \
  third_party/icu/source/common/ruleiter.cpp \
  third_party/icu/source/common/schriter.cpp \
  third_party/icu/source/common/serv.cpp \
  third_party/icu/source/common/servlk.cpp \
  third_party/icu/source/common/servlkf.cpp \
  third_party/icu/source/common/servls.cpp \
  third_party/icu/source/common/servnotf.cpp \
  third_party/icu/source/common/servrbf.cpp \
  third_party/icu/source/common/servslkf.cpp \
  third_party/icu/source/common/sharedobject.cpp \
  third_party/icu/source/common/simpleformatter.cpp \
  third_party/icu/source/common/static_unicode_sets.cpp \
  third_party/icu/source/common/stringpiece.cpp \
  third_party/icu/source/common/stringtriebuilder.cpp \
  third_party/icu/source/common/uarrsort.cpp \
  third_party/icu/source/common/ubidi.cpp \
  third_party/icu/source/common/ubidi_props.cpp \
  third_party/icu/source/common/ubidiln.cpp \
  third_party/icu/source/common/ubiditransform.cpp \
  third_party/icu/source/common/ubidiwrt.cpp \
  third_party/icu/source/common/ubrk.cpp \
  third_party/icu/source/common/ucase.cpp \
  third_party/icu/source/common/ucasemap.cpp \
  third_party/icu/source/common/ucasemap_titlecase_brkiter.cpp \
  third_party/icu/source/common/ucat.cpp \
  third_party/icu/source/common/uchar.cpp \
  third_party/icu/source/common/ucharstrie.cpp \
  third_party/icu/source/common/ucharstriebuilder.cpp \
  third_party/icu/source/common/ucharstrieiterator.cpp \
  third_party/icu/source/common/uchriter.cpp \
  third_party/icu/source/common/ucln_cmn.cpp \
  third_party/icu/source/common/ucmndata.cpp \
  third_party/icu/source/common/ucnv.cpp \
  third_party/icu/source/common/ucnv2022.cpp \
  third_party/icu/source/common/ucnv_bld.cpp \
  third_party/icu/source/common/ucnv_cb.cpp \
  third_party/icu/source/common/ucnv_cnv.cpp \
  third_party/icu/source/common/ucnv_ct.cpp \
  third_party/icu/source/common/ucnv_err.cpp \
  third_party/icu/source/common/ucnv_ext.cpp \
  third_party/icu/source/common/ucnv_io.cpp \
  third_party/icu/source/common/ucnv_lmb.cpp \
  third_party/icu/source/common/ucnv_set.cpp \
  third_party/icu/source/common/ucnv_u16.cpp \
  third_party/icu/source/common/ucnv_u32.cpp \
  third_party/icu/source/common/ucnv_u7.cpp \
  third_party/icu/source/common/ucnv_u8.cpp \
  third_party/icu/source/common/ucnvbocu.cpp \
  third_party/icu/source/common/ucnvdisp.cpp \
  third_party/icu/source/common/ucnvhz.cpp \
  third_party/icu/source/common/ucnvisci.cpp \
  third_party/icu/source/common/ucnvlat1.cpp \
  third_party/icu/source/common/ucnvmbcs.cpp \
  third_party/icu/source/common/ucnvscsu.cpp \
  third_party/icu/source/common/ucnvsel.cpp \
  third_party/icu/source/common/ucol_swp.cpp \
  third_party/icu/source/common/ucptrie.cpp \
  third_party/icu/source/common/ucurr.cpp \
  third_party/icu/source/common/udata.cpp \
  third_party/icu/source/common/udatamem.cpp \
  third_party/icu/source/common/udataswp.cpp \
  third_party/icu/source/common/uenum.cpp \
  third_party/icu/source/common/uhash.cpp \
  third_party/icu/source/common/uhash_us.cpp \
  third_party/icu/source/common/uidna.cpp \
  third_party/icu/source/common/uinit.cpp \
  third_party/icu/source/common/uinvchar.cpp \
  third_party/icu/source/common/uiter.cpp \
  third_party/icu/source/common/ulist.cpp \
  third_party/icu/source/common/uloc.cpp \
  third_party/icu/source/common/uloc_keytype.cpp \
  third_party/icu/source/common/uloc_tag.cpp \
  third_party/icu/source/common/ulocale.cpp \
  third_party/icu/source/common/ulocbuilder.cpp \
  third_party/icu/source/common/umapfile.cpp \
  third_party/icu/source/common/umath.cpp \
  third_party/icu/source/common/umutablecptrie.cpp \
  third_party/icu/source/common/umutex.cpp \
  third_party/icu/source/common/unames.cpp \
  third_party/icu/source/common/unifiedcache.cpp \
  third_party/icu/source/common/unifilt.cpp \
  third_party/icu/source/common/unifunct.cpp \
  third_party/icu/source/common/uniset.cpp \
  third_party/icu/source/common/uniset_closure.cpp \
  third_party/icu/source/common/uniset_props.cpp \
  third_party/icu/source/common/unisetspan.cpp \
  third_party/icu/source/common/unistr.cpp \
  third_party/icu/source/common/unistr_case.cpp \
  third_party/icu/source/common/unistr_case_locale.cpp \
  third_party/icu/source/common/unistr_cnv.cpp \
  third_party/icu/source/common/unistr_props.cpp \
  third_party/icu/source/common/unistr_titlecase_brkiter.cpp \
  third_party/icu/source/common/unorm.cpp \
  third_party/icu/source/common/unormcmp.cpp \
  third_party/icu/source/common/uobject.cpp \
  third_party/icu/source/common/uprops.cpp \
  third_party/icu/source/common/ures_cnv.cpp \
  third_party/icu/source/common/uresbund.cpp \
  third_party/icu/source/common/uresdata.cpp \
  third_party/icu/source/common/usc_impl.cpp \
  third_party/icu/source/common/uscript.cpp \
  third_party/icu/source/common/uscript_props.cpp \
  third_party/icu/source/common/uset.cpp \
  third_party/icu/source/common/uset_props.cpp \
  third_party/icu/source/common/usetiter.cpp \
  third_party/icu/source/common/ushape.cpp \
  third_party/icu/source/common/usprep.cpp \
  third_party/icu/source/common/ustack.cpp \
  third_party/icu/source/common/ustr_cnv.cpp \
  third_party/icu/source/common/ustr_titlecase_brkiter.cpp \
  third_party/icu/source/common/ustr_wcs.cpp \
  third_party/icu/source/common/ustrcase.cpp \
  third_party/icu/source/common/ustrcase_locale.cpp \
  third_party/icu/source/common/ustrenum.cpp \
  third_party/icu/source/common/ustrfmt.cpp \
  third_party/icu/source/common/ustring.cpp \
  third_party/icu/source/common/ustrtrns.cpp \
  third_party/icu/source/common/utext.cpp \
  third_party/icu/source/common/utf_impl.cpp \
  third_party/icu/source/common/util.cpp \
  third_party/icu/source/common/util_props.cpp \
  third_party/icu/source/common/utrace.cpp \
  third_party/icu/source/common/utrie.cpp \
  third_party/icu/source/common/utrie2.cpp \
  third_party/icu/source/common/utrie2_builder.cpp \
  third_party/icu/source/common/utrie_swap.cpp \
  third_party/icu/source/common/uts46.cpp \
  third_party/icu/source/common/utypes.cpp \
  third_party/icu/source/common/uvector.cpp \
  third_party/icu/source/common/uvectr32.cpp \
  third_party/icu/source/common/uvectr64.cpp \
  third_party/icu/source/common/wintz.cpp \
  third_party/icu/source/stubdata/stubdata.cpp

PDFIUM_GROUP_16_COMPILER := $(CXX)
PDFIUM_GROUP_16_DEFINES := '-D_XOPEN_SOURCE=700' '-DNDEBUG' '-DNVALGRIND' '-DDYNAMIC_ANNOTATIONS_ENABLED=0' '-DABSL_ALLOCATOR_NOTHROW=1'
PDFIUM_GROUP_16_INCLUDES := '-I$(PDFIUM_SOURCE)' '-I$(PDFIUM_SOURCE)/third_party/abseil-cpp'
PDFIUM_GROUP_16_SOURCES := \
  third_party/abseil-cpp/absl/time/internal/cctz/src/time_zone_fixed.cc \
  third_party/abseil-cpp/absl/time/internal/cctz/src/time_zone_format.cc \
  third_party/abseil-cpp/absl/time/internal/cctz/src/time_zone_if.cc \
  third_party/abseil-cpp/absl/time/internal/cctz/src/time_zone_impl.cc \
  third_party/abseil-cpp/absl/time/internal/cctz/src/time_zone_info.cc \
  third_party/abseil-cpp/absl/time/internal/cctz/src/time_zone_libc.cc \
  third_party/abseil-cpp/absl/time/internal/cctz/src/time_zone_lookup.cc \
  third_party/abseil-cpp/absl/time/internal/cctz/src/time_zone_posix.cc \
  third_party/abseil-cpp/absl/time/internal/cctz/src/zone_info_source.cc

PDFIUM_GROUP_17_COMPILER := $(CXX)
PDFIUM_GROUP_17_DEFINES := '-D__STDC_CONSTANT_MACROS' '-D__STDC_FORMAT_MACROS' '-D_FORTIFY_SOURCE=2' '-DNDEBUG' '-DNVALGRIND' '-DDYNAMIC_ANNOTATIONS_ENABLED=0' '-DAFDKO_VERSION_STRING="hyper-internal"'
PDFIUM_GROUP_17_INCLUDES := '-I$(PDFIUM_SOURCE)' '-I$(PDFIUM_SOURCE)/third_party/afdko/shared/include' '-I$(PDFIUM_SOURCE)/third_party/afdko/shared' '-I$(PDFIUM_SOURCE)/third_party/afdko/shared/cffwrite' '-I$(PDFIUM_SOURCE)/third_party/afdko/shared/absfont' '-I$(PDFIUM_SOURCE)/third_party/afdko/shared/support' '-I$(PDFIUM_SOURCE)/third_party/afdko/shared/resource'
PDFIUM_GROUP_17_SOURCES := \
  third_party/afdko/shared/absfont/absfont.cpp \
  third_party/afdko/shared/absfont/absfont_afm.cpp \
  third_party/afdko/shared/absfont/absfont_compare.cpp \
  third_party/afdko/shared/absfont/absfont_desc.cpp \
  third_party/afdko/shared/absfont/absfont_draw.cpp \
  third_party/afdko/shared/absfont/absfont_dump.cpp \
  third_party/afdko/shared/absfont/absfont_metrics.cpp \
  third_party/afdko/shared/absfont/absfont_path.cpp \
  third_party/afdko/shared/cffread_abs.cpp \
  third_party/afdko/shared/cffwrite/cffwrite.cpp \
  third_party/afdko/shared/cffwrite/cffwrite_charset.cpp \
  third_party/afdko/shared/cffwrite/cffwrite_dict.cpp \
  third_party/afdko/shared/cffwrite/cffwrite_encoding.cpp \
  third_party/afdko/shared/cffwrite/cffwrite_fdselect.cpp \
  third_party/afdko/shared/cffwrite/cffwrite_sindex.cpp \
  third_party/afdko/shared/cffwrite/cffwrite_subr.cpp \
  third_party/afdko/shared/cffwrite/cffwrite_t2cstr.cpp \
  third_party/afdko/shared/cffwrite/cffwrite_varstore.cpp \
  third_party/afdko/shared/goadb.cpp \
  third_party/afdko/shared/namesupport.cpp \
  third_party/afdko/shared/pstoken.cpp \
  third_party/afdko/shared/sfile.cpp \
  third_party/afdko/shared/sfntread.cpp \
  third_party/afdko/shared/sfntwrite.cpp \
  third_party/afdko/shared/slogger.cpp \
  third_party/afdko/shared/t1cstr.cpp \
  third_party/afdko/shared/t1read.cpp \
  third_party/afdko/shared/t2cstr.cpp \
  third_party/afdko/shared/varsupport.cpp

PDFIUM_GROUP_18_COMPILER := $(CXX)
PDFIUM_GROUP_18_DEFINES := '-D__STDC_CONSTANT_MACROS' '-D__STDC_FORMAT_MACROS' '-D_FORTIFY_SOURCE=2' '-DNDEBUG' '-DNVALGRIND' '-DDYNAMIC_ANNOTATIONS_ENABLED=0' '-DHAVE_LIBPNG=0' '-DHAVE_LIBJPEG=0' '-DHAVE_LIBTIFF=0' '-DHAVE_LIBGIF=0' '-DHAVE_LIBJP2K=0' '-DHAVE_LIBWEBP=0' '-DHAVE_LIBZ=0' '-DVERSION="hyper-internal"' '-DHAVE_FMEMOPEN=1' '-DHAVE_LIBUNGIF=0' '-DHAVE_LIBWEBP_ANIM=0' '-DNO_CONSOLE_IO'
PDFIUM_GROUP_18_INCLUDES := '-I$(PDFIUM_SOURCE)' '-I$(PDFIUM_SOURCE)/third_party/jbig2enc/src' '-I$(PDFIUM_SOURCE)/third_party/leptonica/src'
PDFIUM_GROUP_18_SOURCES := \
  third_party/jbig2enc/src/jbig2arith.cc \
  third_party/jbig2enc/src/jbig2comparator.cc \
  third_party/jbig2enc/src/jbig2enc.cc \
  third_party/jbig2enc/src/jbig2sym.cc

PDFIUM_GROUP_19_COMPILER := $(CXX)
PDFIUM_GROUP_19_DEFINES := '-D__STDC_CONSTANT_MACROS' '-D__STDC_FORMAT_MACROS' '-D_FORTIFY_SOURCE=2' '-DNDEBUG' '-DNVALGRIND' '-DDYNAMIC_ANNOTATIONS_ENABLED=0' '-DOPJ_STATIC' '-DPDF_ENABLE_BROTLI' '-DPDF_USE_AGG' '-DFPDF_IMPLEMENTATION' '-DFT_CONFIG_MODULES_H="freetype-custom-config/ftmodule.h"' '-DFT_CONFIG_OPTIONS_H="freetype-custom-config/ftoption.h"' '-DU_USING_ICU_NAMESPACE=0' '-DU_ENABLE_DYLOAD=0' '-DUSE_CHROMIUM_ICU=1' '-DU_ENABLE_TRACING=1' '-DU_ENABLE_RESOURCE_TRACING=0' '-DU_STATIC_IMPLEMENTATION' '-DICU_UTIL_DATA_IMPL=ICU_UTIL_DATA_FILE'
PDFIUM_GROUP_19_INCLUDES := '-I$(PDFIUM_SOURCE)' '-I$(PDFIUM_SOURCE)/third_party/freetype/include' '-I$(PDFIUM_SOURCE)/third_party/freetype/src/include' '-I$(PDFIUM_SOURCE)/third_party/abseil-cpp' '-I$(PDFIUM_SOURCE)/third_party/icu/source/common' '-I$(PDFIUM_SOURCE)/third_party/icu/source/i18n'
PDFIUM_GROUP_19_SOURCES := \
  fpdfsdk/formfiller/cffl_button.cpp \
  fpdfsdk/formfiller/cffl_checkbox.cpp \
  fpdfsdk/formfiller/cffl_combobox.cpp \
  fpdfsdk/formfiller/cffl_fieldaction.cpp \
  fpdfsdk/formfiller/cffl_formfield.cpp \
  fpdfsdk/formfiller/cffl_interactiveformfiller.cpp \
  fpdfsdk/formfiller/cffl_listbox.cpp \
  fpdfsdk/formfiller/cffl_perwindowdata.cpp \
  fpdfsdk/formfiller/cffl_pushbutton.cpp \
  fpdfsdk/formfiller/cffl_radiobutton.cpp \
  fpdfsdk/formfiller/cffl_textfield.cpp \
  fpdfsdk/formfiller/cffl_textobject.cpp \
  fpdfsdk/pwl/cpwl_button.cpp \
  fpdfsdk/pwl/cpwl_caret.cpp \
  fpdfsdk/pwl/cpwl_cbbutton.cpp \
  fpdfsdk/pwl/cpwl_cblistbox.cpp \
  fpdfsdk/pwl/cpwl_combo_box.cpp \
  fpdfsdk/pwl/cpwl_edit.cpp \
  fpdfsdk/pwl/cpwl_edit_impl.cpp \
  fpdfsdk/pwl/cpwl_list_box.cpp \
  fpdfsdk/pwl/cpwl_list_ctrl.cpp \
  fpdfsdk/pwl/cpwl_sbbutton.cpp \
  fpdfsdk/pwl/cpwl_scroll_bar.cpp \
  fpdfsdk/pwl/cpwl_special_button.cpp \
  fpdfsdk/pwl/cpwl_wnd.cpp

PDFIUM_GROUP_20_COMPILER := $(CXX)
PDFIUM_GROUP_20_DEFINES := '-D__STDC_CONSTANT_MACROS' '-D__STDC_FORMAT_MACROS' '-D_FORTIFY_SOURCE=2' '-DNDEBUG' '-DNVALGRIND' '-DDYNAMIC_ANNOTATIONS_ENABLED=0' '-DOPJ_STATIC' '-DPDF_ENABLE_BROTLI' '-DPDF_USE_AGG' '-DFPDF_IMPLEMENTATION' '-DFT_CONFIG_MODULES_H="freetype-custom-config/ftmodule.h"' '-DFT_CONFIG_OPTIONS_H="freetype-custom-config/ftoption.h"' '-DU_USING_ICU_NAMESPACE=0' '-DU_ENABLE_DYLOAD=0' '-DUSE_CHROMIUM_ICU=1' '-DU_ENABLE_TRACING=1' '-DU_ENABLE_RESOURCE_TRACING=0' '-DU_STATIC_IMPLEMENTATION' '-DICU_UTIL_DATA_IMPL=ICU_UTIL_DATA_FILE' '-DAFDKO_VERSION_STRING="hyper-internal"' '-DHAVE_LIBPNG=0' '-DHAVE_LIBJPEG=0' '-DHAVE_LIBTIFF=0' '-DHAVE_LIBGIF=0' '-DHAVE_LIBJP2K=0' '-DHAVE_LIBWEBP=0' '-DHAVE_LIBZ=0' '-DVERSION="hyper-internal"' '-DHAVE_FMEMOPEN=1' '-DHAVE_LIBUNGIF=0' '-DHAVE_LIBWEBP_ANIM=0' '-DNO_CONSOLE_IO'
PDFIUM_GROUP_20_INCLUDES := '-I$(PDFIUM_SOURCE)' '-I$(PDFIUM_SOURCE)/third_party/freetype/include' '-I$(PDFIUM_SOURCE)/third_party/freetype/src/include' '-I$(PDFIUM_SOURCE)/third_party/abseil-cpp' '-I$(PDFIUM_SOURCE)/third_party/icu/source/common' '-I$(PDFIUM_SOURCE)/third_party/icu/source/i18n' '-I$(PDFIUM_SOURCE)/third_party/afdko/shared/include' '-I$(PDFIUM_SOURCE)/third_party/afdko/shared' '-I$(PDFIUM_SOURCE)/third_party/afdko/shared/cffwrite' '-I$(PDFIUM_SOURCE)/third_party/afdko/shared/absfont' '-I$(PDFIUM_SOURCE)/third_party/afdko/shared/support' '-I$(PDFIUM_SOURCE)/third_party/afdko/shared/resource' '-I$(PDFIUM_SOURCE)/third_party/brotli/include' '-I$(PDFIUM_SOURCE)/third_party/harfbuzz/src/src' '-I$(PDFIUM_SOURCE)/third_party/harfbuzz' '-I$(PDFIUM_SOURCE)/third_party/jbig2enc/src' '-I$(PDFIUM_SOURCE)/third_party/leptonica/src'
PDFIUM_GROUP_20_SOURCES := \
  fpdfsdk/cpdfsdk_annot.cpp \
  fpdfsdk/cpdfsdk_annotiteration.cpp \
  fpdfsdk/cpdfsdk_annotiterator.cpp \
  fpdfsdk/cpdfsdk_appstream.cpp \
  fpdfsdk/cpdfsdk_baannot.cpp \
  fpdfsdk/cpdfsdk_customaccess.cpp \
  fpdfsdk/cpdfsdk_filewriteadapter.cpp \
  fpdfsdk/cpdfsdk_formfillenvironment.cpp \
  fpdfsdk/cpdfsdk_helpers.cpp \
  fpdfsdk/cpdfsdk_interactiveform.cpp \
  fpdfsdk/cpdfsdk_pageview.cpp \
  fpdfsdk/cpdfsdk_pauseadapter.cpp \
  fpdfsdk/cpdfsdk_renderpage.cpp \
  fpdfsdk/cpdfsdk_widget.cpp \
  fpdfsdk/fpdf_annot.cpp \
  fpdfsdk/fpdf_attachment.cpp \
  fpdfsdk/fpdf_catalog.cpp \
  fpdfsdk/fpdf_compress.cpp \
  fpdfsdk/fpdf_dataavail.cpp \
  fpdfsdk/fpdf_doc.cpp \
  fpdfsdk/fpdf_editimg.cpp \
  fpdfsdk/fpdf_editpage.cpp \
  fpdfsdk/fpdf_editpath.cpp \
  fpdfsdk/fpdf_edittext.cpp \
  fpdfsdk/fpdf_ext.cpp \
  fpdfsdk/fpdf_flatten.cpp \
  fpdfsdk/fpdf_formfill.cpp \
  fpdfsdk/fpdf_javascript.cpp \
  fpdfsdk/fpdf_ppo.cpp \
  fpdfsdk/fpdf_progressive.cpp \
  fpdfsdk/fpdf_save.cpp \
  fpdfsdk/fpdf_searchex.cpp \
  fpdfsdk/fpdf_signature.cpp \
  fpdfsdk/fpdf_structtree.cpp \
  fpdfsdk/fpdf_sysfontinfo.cpp \
  fpdfsdk/fpdf_text.cpp \
  fpdfsdk/fpdf_thumbnail.cpp \
  fpdfsdk/fpdf_transformpage.cpp \
  fpdfsdk/fpdf_view.cpp \
  fpdfsdk/hyper_jbig2_wrap.cc \
  fpdfsdk/hyper_type1_wrap.cc

PDFIUM_GROUP_21_COMPILER := $(CXX)
PDFIUM_GROUP_21_DEFINES := '-D__STDC_CONSTANT_MACROS' '-D__STDC_FORMAT_MACROS' '-D_FORTIFY_SOURCE=2' '-DNDEBUG' '-DNVALGRIND' '-DDYNAMIC_ANNOTATIONS_ENABLED=0' '-DOPJ_STATIC' '-DPDF_ENABLE_BROTLI' '-DPDF_USE_AGG' '-DFT_CONFIG_MODULES_H="freetype-custom-config/ftmodule.h"' '-DFT_CONFIG_OPTIONS_H="freetype-custom-config/ftoption.h"' '-DU_USING_ICU_NAMESPACE=0' '-DU_ENABLE_DYLOAD=0' '-DUSE_CHROMIUM_ICU=1' '-DU_ENABLE_TRACING=1' '-DU_ENABLE_RESOURCE_TRACING=0' '-DU_STATIC_IMPLEMENTATION' '-DICU_UTIL_DATA_IMPL=ICU_UTIL_DATA_FILE'
PDFIUM_GROUP_21_INCLUDES := '-I$(PDFIUM_SOURCE)' '-I$(PDFIUM_SOURCE)/third_party/freetype/include' '-I$(PDFIUM_SOURCE)/third_party/freetype/src/include' '-I$(PDFIUM_SOURCE)/third_party/abseil-cpp' '-I$(PDFIUM_SOURCE)/third_party/icu/source/common' '-I$(PDFIUM_SOURCE)/third_party/icu/source/i18n'
PDFIUM_GROUP_21_SOURCES := \
  core/fdrm/fx_crypt.cpp \
  core/fdrm/fx_crypt_aes.cpp \
  core/fdrm/fx_crypt_sha.cpp \
  core/fpdfapi/cmaps/CNS1/B5pc-H_0.cpp \
  core/fpdfapi/cmaps/CNS1/B5pc-V_0.cpp \
  core/fpdfapi/cmaps/CNS1/CNS-EUC-H_0.cpp \
  core/fpdfapi/cmaps/CNS1/CNS-EUC-V_0.cpp \
  core/fpdfapi/cmaps/CNS1/ETen-B5-H_0.cpp \
  core/fpdfapi/cmaps/CNS1/ETen-B5-V_0.cpp \
  core/fpdfapi/cmaps/CNS1/ETenms-B5-H_0.cpp \
  core/fpdfapi/cmaps/CNS1/ETenms-B5-V_0.cpp \
  core/fpdfapi/cmaps/CNS1/HKscs-B5-H_5.cpp \
  core/fpdfapi/cmaps/CNS1/HKscs-B5-V_5.cpp \
  core/fpdfapi/cmaps/CNS1/UniCNS-UCS2-H_3.cpp \
  core/fpdfapi/cmaps/CNS1/UniCNS-UCS2-V_3.cpp \
  core/fpdfapi/cmaps/CNS1/UniCNS-UTF16-H_0.cpp \
  core/fpdfapi/cmaps/GB1/GB-EUC-H_0.cpp \
  core/fpdfapi/cmaps/GB1/GB-EUC-V_0.cpp \
  core/fpdfapi/cmaps/GB1/GBK-EUC-H_2.cpp \
  core/fpdfapi/cmaps/GB1/GBK-EUC-V_2.cpp \
  core/fpdfapi/cmaps/GB1/GBK2K-H_5.cpp \
  core/fpdfapi/cmaps/GB1/GBK2K-V_5.cpp \
  core/fpdfapi/cmaps/GB1/GBKp-EUC-H_2.cpp \
  core/fpdfapi/cmaps/GB1/GBKp-EUC-V_2.cpp \
  core/fpdfapi/cmaps/GB1/GBpc-EUC-H_0.cpp \
  core/fpdfapi/cmaps/GB1/GBpc-EUC-V_0.cpp \
  core/fpdfapi/cmaps/GB1/UniGB-UCS2-H_4.cpp \
  core/fpdfapi/cmaps/GB1/UniGB-UCS2-V_4.cpp \
  core/fpdfapi/cmaps/Japan1/83pv-RKSJ-H_1.cpp \
  core/fpdfapi/cmaps/Japan1/90ms-RKSJ-H_2.cpp \
  core/fpdfapi/cmaps/Japan1/90ms-RKSJ-V_2.cpp \
  core/fpdfapi/cmaps/Japan1/90msp-RKSJ-H_2.cpp \
  core/fpdfapi/cmaps/Japan1/90msp-RKSJ-V_2.cpp \
  core/fpdfapi/cmaps/Japan1/90pv-RKSJ-H_1.cpp \
  core/fpdfapi/cmaps/Japan1/Add-RKSJ-H_1.cpp \
  core/fpdfapi/cmaps/Japan1/Add-RKSJ-V_1.cpp \
  core/fpdfapi/cmaps/Japan1/EUC-H_1.cpp \
  core/fpdfapi/cmaps/Japan1/EUC-V_1.cpp \
  core/fpdfapi/cmaps/Japan1/Ext-RKSJ-H_2.cpp \
  core/fpdfapi/cmaps/Japan1/Ext-RKSJ-V_2.cpp \
  core/fpdfapi/cmaps/Japan1/H_1.cpp \
  core/fpdfapi/cmaps/Japan1/UniJIS-UCS2-HW-H_4.cpp \
  core/fpdfapi/cmaps/Japan1/UniJIS-UCS2-HW-V_4.cpp \
  core/fpdfapi/cmaps/Japan1/UniJIS-UCS2-H_4.cpp \
  core/fpdfapi/cmaps/Japan1/UniJIS-UCS2-V_4.cpp \
  core/fpdfapi/cmaps/Japan1/V_1.cpp \
  core/fpdfapi/cmaps/Korea1/KSC-EUC-H_0.cpp \
  core/fpdfapi/cmaps/Korea1/KSC-EUC-V_0.cpp \
  core/fpdfapi/cmaps/Korea1/KSCms-UHC-HW-H_1.cpp \
  core/fpdfapi/cmaps/Korea1/KSCms-UHC-HW-V_1.cpp \
  core/fpdfapi/cmaps/Korea1/KSCms-UHC-H_1.cpp \
  core/fpdfapi/cmaps/Korea1/KSCms-UHC-V_1.cpp \
  core/fpdfapi/cmaps/Korea1/KSCpc-EUC-H_0.cpp \
  core/fpdfapi/cmaps/Korea1/UniKS-UCS2-H_1.cpp \
  core/fpdfapi/cmaps/Korea1/UniKS-UCS2-V_1.cpp \
  core/fpdfapi/cmaps/Korea1/UniKS-UTF16-H_0.cpp \
  core/fpdfapi/cmaps/fpdf_cmaps.cpp \
  core/fpdfapi/font/cpdf_cid2unicodemap.cpp \
  core/fpdfapi/font/cpdf_cidfont.cpp \
  core/fpdfapi/font/cpdf_cmap.cpp \
  core/fpdfapi/font/cpdf_cmapparser.cpp \
  core/fpdfapi/font/cpdf_facebasedsimplefont.cpp \
  core/fpdfapi/font/cpdf_font.cpp \
  core/fpdfapi/font/cpdf_fontencoding.cpp \
  core/fpdfapi/font/cpdf_fontglobals.cpp \
  core/fpdfapi/font/cpdf_simplefont.cpp \
  core/fpdfapi/font/cpdf_stockfontarray.cpp \
  core/fpdfapi/font/cpdf_tounicodemap.cpp \
  core/fpdfapi/font/cpdf_truetypefont.cpp \
  core/fpdfapi/font/cpdf_type1font.cpp \
  core/fpdfapi/font/cpdf_type3char.cpp \
  core/fpdfapi/font/cpdf_type3font.cpp \
  core/fpdfapi/page/cpdf_allstates.cpp \
  core/fpdfapi/page/cpdf_annotcontext.cpp \
  core/fpdfapi/page/cpdf_basedcs.cpp \
  core/fpdfapi/page/cpdf_clippath.cpp \
  core/fpdfapi/page/cpdf_color.cpp \
  core/fpdfapi/page/cpdf_colorspace.cpp \
  core/fpdfapi/page/cpdf_colorstate.cpp \
  core/fpdfapi/page/cpdf_contentmarkitem.cpp \
  core/fpdfapi/page/cpdf_contentmarks.cpp \
  core/fpdfapi/page/cpdf_contentparser.cpp \
  core/fpdfapi/page/cpdf_devicecs.cpp \
  core/fpdfapi/page/cpdf_dib.cpp \
  core/fpdfapi/page/cpdf_docpagedata.cpp \
  core/fpdfapi/page/cpdf_expintfunc.cpp \
  core/fpdfapi/page/cpdf_form.cpp \
  core/fpdfapi/page/cpdf_formobject.cpp \
  core/fpdfapi/page/cpdf_function.cpp \
  core/fpdfapi/page/cpdf_generalstate.cpp \
  core/fpdfapi/page/cpdf_graphicstates.cpp \
  core/fpdfapi/page/cpdf_iccprofile.cpp \
  core/fpdfapi/page/cpdf_image.cpp \
  core/fpdfapi/page/cpdf_imageloader.cpp \
  core/fpdfapi/page/cpdf_imageobject.cpp \
  core/fpdfapi/page/cpdf_indexedcs.cpp \
  core/fpdfapi/page/cpdf_meshstream.cpp \
  core/fpdfapi/page/cpdf_occontext.cpp \
  core/fpdfapi/page/cpdf_page.cpp \
  core/fpdfapi/page/cpdf_pageimagecache.cpp \
  core/fpdfapi/page/cpdf_pagemodule.cpp \
  core/fpdfapi/page/cpdf_pageobject.cpp \
  core/fpdfapi/page/cpdf_pageobjectholder.cpp \
  core/fpdfapi/page/cpdf_path.cpp \
  core/fpdfapi/page/cpdf_pathobject.cpp \
  core/fpdfapi/page/cpdf_pattern.cpp \
  core/fpdfapi/page/cpdf_patterncs.cpp \
  core/fpdfapi/page/cpdf_psengine.cpp \
  core/fpdfapi/page/cpdf_psfunc.cpp \
  core/fpdfapi/page/cpdf_sampledfunc.cpp \
  core/fpdfapi/page/cpdf_shadingobject.cpp \
  core/fpdfapi/page/cpdf_shadingpattern.cpp \
  core/fpdfapi/page/cpdf_stitchfunc.cpp \
  core/fpdfapi/page/cpdf_streamcontentparser.cpp \
  core/fpdfapi/page/cpdf_streamparser.cpp \
  core/fpdfapi/page/cpdf_textobject.cpp \
  core/fpdfapi/page/cpdf_textstate.cpp \
  core/fpdfapi/page/cpdf_tilingpattern.cpp \
  core/fpdfapi/page/cpdf_transferfunc.cpp \
  core/fpdfapi/page/cpdf_transferfuncdib.cpp \
  core/fpdfapi/page/cpdf_transparency.cpp \
  core/fpdfapi/page/jpx_decode_conversion.cpp \
  core/fpdfapi/parser/cfdf_document.cpp \
  core/fpdfapi/parser/cpdf_array.cpp \
  core/fpdfapi/parser/cpdf_boolean.cpp \
  core/fpdfapi/parser/cpdf_cross_ref_avail.cpp \
  core/fpdfapi/parser/cpdf_cross_ref_table.cpp \
  core/fpdfapi/parser/cpdf_crypto_handler.cpp \
  core/fpdfapi/parser/cpdf_data_avail.cpp \
  core/fpdfapi/parser/cpdf_dictionary.cpp \
  core/fpdfapi/parser/cpdf_document.cpp \
  core/fpdfapi/parser/cpdf_encryptor.cpp \
  core/fpdfapi/parser/cpdf_flateencoder.cpp \
  core/fpdfapi/parser/cpdf_hint_tables.cpp \
  core/fpdfapi/parser/cpdf_indirect_object_holder.cpp \
  core/fpdfapi/parser/cpdf_linearized_header.cpp \
  core/fpdfapi/parser/cpdf_name.cpp \
  core/fpdfapi/parser/cpdf_null.cpp \
  core/fpdfapi/parser/cpdf_number.cpp \
  core/fpdfapi/parser/cpdf_object.cpp \
  core/fpdfapi/parser/cpdf_object_avail.cpp \
  core/fpdfapi/parser/cpdf_object_stream.cpp \
  core/fpdfapi/parser/cpdf_object_walker.cpp \
  core/fpdfapi/parser/cpdf_page_object_avail.cpp \
  core/fpdfapi/parser/cpdf_parser.cpp \
  core/fpdfapi/parser/cpdf_read_validator.cpp \
  core/fpdfapi/parser/cpdf_reference.cpp \
  core/fpdfapi/parser/cpdf_security_handler.cpp \
  core/fpdfapi/parser/cpdf_simple_parser.cpp \
  core/fpdfapi/parser/cpdf_stream.cpp \
  core/fpdfapi/parser/cpdf_stream_acc.cpp \
  core/fpdfapi/parser/cpdf_string.cpp \
  core/fpdfapi/parser/cpdf_syntax_parser.cpp \
  core/fpdfapi/parser/fpdf_parser_decode.cpp \
  core/fpdfapi/parser/fpdf_parser_utility.cpp \
  core/fpdfapi/parser/object_tree_traversal_util.cpp \
  core/fpdfapi/render/cpdf_devicebuffer.cpp \
  core/fpdfapi/render/cpdf_docrenderdata.cpp \
  core/fpdfapi/render/cpdf_imagerenderer.cpp \
  core/fpdfapi/render/cpdf_pagerendercontext.cpp \
  core/fpdfapi/render/cpdf_progressiverenderer.cpp \
  core/fpdfapi/render/cpdf_rendercontext.cpp \
  core/fpdfapi/render/cpdf_renderoptions.cpp \
  core/fpdfapi/render/cpdf_rendershading.cpp \
  core/fpdfapi/render/cpdf_renderstatus.cpp \
  core/fpdfapi/render/cpdf_rendertiling.cpp \
  core/fpdfapi/render/cpdf_textrenderer.cpp \
  core/fpdfapi/render/cpdf_type3cache.cpp \
  core/fpdfapi/render/cpdf_type3glyphmap.cpp \
  core/fpdfdoc/cpdf_aaction.cpp \
  core/fpdfdoc/cpdf_action.cpp \
  core/fpdfdoc/cpdf_annot.cpp \
  core/fpdfdoc/cpdf_annotlist.cpp \
  core/fpdfdoc/cpdf_apsettings.cpp \
  core/fpdfdoc/cpdf_bafontmap.cpp \
  core/fpdfdoc/cpdf_bookmark.cpp \
  core/fpdfdoc/cpdf_bookmarktree.cpp \
  core/fpdfdoc/cpdf_color_utils.cpp \
  core/fpdfdoc/cpdf_defaultappearance.cpp \
  core/fpdfdoc/cpdf_dest.cpp \
  core/fpdfdoc/cpdf_filespec.cpp \
  core/fpdfdoc/cpdf_formcontrol.cpp \
  core/fpdfdoc/cpdf_formfield.cpp \
  core/fpdfdoc/cpdf_generateap.cpp \
  core/fpdfdoc/cpdf_icon.cpp \
  core/fpdfdoc/cpdf_iconfit.cpp \
  core/fpdfdoc/cpdf_interactiveform.cpp \
  core/fpdfdoc/cpdf_link.cpp \
  core/fpdfdoc/cpdf_linklist.cpp \
  core/fpdfdoc/cpdf_metadata.cpp \
  core/fpdfdoc/cpdf_nametree.cpp \
  core/fpdfdoc/cpdf_numbertree.cpp \
  core/fpdfdoc/cpdf_pagelabel.cpp \
  core/fpdfdoc/cpdf_structelement.cpp \
  core/fpdfdoc/cpdf_structtree.cpp \
  core/fpdfdoc/cpdf_viewerpreferences.cpp \
  core/fpdfdoc/cpvt_fontmap.cpp \
  core/fpdfdoc/cpvt_section.cpp \
  core/fpdfdoc/cpvt_variabletext.cpp \
  core/fpdfdoc/cpvt_word.cpp \
  core/fpdfdoc/cpvt_wordinfo.cpp \
  core/fpdftext/cpdf_linkextract.cpp \
  core/fpdftext/cpdf_textpage.cpp \
  core/fpdftext/cpdf_textpagefind.cpp \
  core/fpdftext/unicodenormalizationdata.cpp \
  core/fxge/agg/cfx_agg_bitmapcomposer.cpp \
  core/fxge/agg/cfx_agg_cliprgn.cpp \
  core/fxge/agg/cfx_agg_devicedriver.cpp \
  core/fxge/agg/cfx_agg_imagerenderer.cpp \
  core/fxge/apple/capple_platform.cpp \
  core/fxge/apple/cquartz_2d.cpp \
  core/fxge/apple/fx_apple_impl.cpp \
  core/fxge/calculate_pitch.cpp \
  core/fxge/cfx_charmap_resolver.cpp \
  core/fxge/cfx_color.cpp \
  core/fxge/cfx_cttgsubtable.cpp \
  core/fxge/cfx_drawutils.cpp \
  core/fxge/cfx_face.cpp \
  core/fxge/cfx_folderfontinfo.cpp \
  core/fxge/cfx_font.cpp \
  core/fxge/cfx_fontmapper.cpp \
  core/fxge/cfx_fontmgr.cpp \
  core/fxge/cfx_gemodule.cpp \
  core/fxge/cfx_glyphbitmap.cpp \
  core/fxge/cfx_glyphcache.cpp \
  core/fxge/cfx_graphstate.cpp \
  core/fxge/cfx_graphstatedata.cpp \
  core/fxge/cfx_path.cpp \
  core/fxge/cfx_renderdevice.cpp \
  core/fxge/cfx_standardfont.cpp \
  core/fxge/cfx_substfont.cpp \
  core/fxge/dib/blend.cpp \
  core/fxge/dib/cfx_bitmapstorer.cpp \
  core/fxge/dib/cfx_cmyk_to_srgb.cpp \
  core/fxge/dib/cfx_dibbase.cpp \
  core/fxge/dib/cfx_dibitmap.cpp \
  core/fxge/dib/cfx_imagestretcher.cpp \
  core/fxge/dib/cfx_imagetransformer.cpp \
  core/fxge/dib/cfx_scanlinecompositor.cpp \
  core/fxge/dib/cstretchengine.cpp \
  core/fxge/dib/fx_dib.cpp \
  core/fxge/fontdata/chromefontdata/FoxitDingbats.cpp \
  core/fxge/fontdata/chromefontdata/FoxitFixed.cpp \
  core/fxge/fontdata/chromefontdata/FoxitFixedBold.cpp \
  core/fxge/fontdata/chromefontdata/FoxitFixedBoldItalic.cpp \
  core/fxge/fontdata/chromefontdata/FoxitFixedItalic.cpp \
  core/fxge/fontdata/chromefontdata/FoxitSans.cpp \
  core/fxge/fontdata/chromefontdata/FoxitSansBold.cpp \
  core/fxge/fontdata/chromefontdata/FoxitSansBoldItalic.cpp \
  core/fxge/fontdata/chromefontdata/FoxitSansItalic.cpp \
  core/fxge/fontdata/chromefontdata/FoxitSansMM.cpp \
  core/fxge/fontdata/chromefontdata/FoxitSerif.cpp \
  core/fxge/fontdata/chromefontdata/FoxitSerifBold.cpp \
  core/fxge/fontdata/chromefontdata/FoxitSerifBoldItalic.cpp \
  core/fxge/fontdata/chromefontdata/FoxitSerifItalic.cpp \
  core/fxge/fontdata/chromefontdata/FoxitSerifMM.cpp \
  core/fxge/fontdata/chromefontdata/FoxitSymbol.cpp \
  core/fxge/freetype/fx_freetype.cpp \
  core/fxge/fx_font.cpp \
  core/fxge/renderdevicedriver_iface.cpp \
  core/fxge/text_char_pos.cpp \
  core/fxge/text_glyph_pos.cpp \
  fxjs/cjs_event_context_stub.cpp \
  fxjs/cjs_runtimestub.cpp \
  fxjs/ijs_runtime.cpp

PDFIUM_GROUP_22_COMPILER := $(CXX)
PDFIUM_GROUP_22_DEFINES := '-D__STDC_CONSTANT_MACROS' '-D__STDC_FORMAT_MACROS' '-D_FORTIFY_SOURCE=2' '-DNDEBUG' '-DNVALGRIND' '-DDYNAMIC_ANNOTATIONS_ENABLED=0' '-DOPJ_STATIC' '-DPDF_ENABLE_BROTLI' '-DPDF_USE_AGG' '-DFT_CONFIG_MODULES_H="freetype-custom-config/ftmodule.h"' '-DFT_CONFIG_OPTIONS_H="freetype-custom-config/ftoption.h"' '-DU_USING_ICU_NAMESPACE=0' '-DU_ENABLE_DYLOAD=0' '-DUSE_CHROMIUM_ICU=1' '-DU_ENABLE_TRACING=1' '-DU_ENABLE_RESOURCE_TRACING=0' '-DU_STATIC_IMPLEMENTATION' '-DICU_UTIL_DATA_IMPL=ICU_UTIL_DATA_FILE'
PDFIUM_GROUP_22_INCLUDES := '-I$(PDFIUM_SOURCE)' '-I$(PDFIUM_SOURCE)/third_party/freetype/include' '-I$(PDFIUM_SOURCE)/third_party/freetype/src/include' '-I$(PDFIUM_SOURCE)/third_party/abseil-cpp' '-I$(PDFIUM_SOURCE)/third_party/icu/source/common' '-I$(PDFIUM_SOURCE)/third_party/icu/source/i18n' '-I$(PDFIUM_SOURCE)/third_party/dragonbox/src/include'
PDFIUM_GROUP_22_SOURCES := \
  core/fpdfapi/edit/cpdf_contentstream_write_utils.cpp

PDFIUM_GROUP_23_COMPILER := $(CXX)
PDFIUM_GROUP_23_DEFINES := '-D__STDC_CONSTANT_MACROS' '-D__STDC_FORMAT_MACROS' '-D_FORTIFY_SOURCE=2' '-DNDEBUG' '-DNVALGRIND' '-DDYNAMIC_ANNOTATIONS_ENABLED=0' '-DOPJ_STATIC' '-DPDF_ENABLE_BROTLI' '-DPDF_USE_AGG' '-DFT_CONFIG_MODULES_H="freetype-custom-config/ftmodule.h"' '-DFT_CONFIG_OPTIONS_H="freetype-custom-config/ftoption.h"' '-DU_USING_ICU_NAMESPACE=0' '-DU_ENABLE_DYLOAD=0' '-DUSE_CHROMIUM_ICU=1' '-DU_ENABLE_TRACING=1' '-DU_ENABLE_RESOURCE_TRACING=0' '-DU_STATIC_IMPLEMENTATION' '-DICU_UTIL_DATA_IMPL=ICU_UTIL_DATA_FILE'
PDFIUM_GROUP_23_INCLUDES := '-I$(PDFIUM_SOURCE)' '-I$(PDFIUM_SOURCE)/third_party/freetype/include' '-I$(PDFIUM_SOURCE)/third_party/freetype/src/include' '-I$(PDFIUM_SOURCE)/third_party/abseil-cpp' '-I$(PDFIUM_SOURCE)/third_party/icu/source/common' '-I$(PDFIUM_SOURCE)/third_party/icu/source/i18n' '-I$(PDFIUM_SOURCE)/third_party/fast_float/src/include'
PDFIUM_GROUP_23_SOURCES := \
  core/fxcrt/binary_buffer.cpp \
  core/fxcrt/bytestring.cpp \
  core/fxcrt/bytestring_pool.cpp \
  core/fxcrt/cfx_bidi_resolver.cpp \
  core/fxcrt/cfx_bitstream.cpp \
  core/fxcrt/cfx_datetime.cpp \
  core/fxcrt/cfx_fileaccess_posix.cpp \
  core/fxcrt/cfx_fileaccess_stream.cpp \
  core/fxcrt/cfx_read_only_container_stream.cpp \
  core/fxcrt/cfx_read_only_span_stream.cpp \
  core/fxcrt/cfx_seekablestreamproxy.cpp \
  core/fxcrt/cfx_timer.cpp \
  core/fxcrt/debug/alias.cc \
  core/fxcrt/fx_bidi.cpp \
  core/fxcrt/fx_codepage.cpp \
  core/fxcrt/fx_coordinates.cpp \
  core/fxcrt/fx_extension.cpp \
  core/fxcrt/fx_folder_posix.cpp \
  core/fxcrt/fx_memory.cpp \
  core/fxcrt/fx_memory_malloc.cpp \
  core/fxcrt/fx_number.cpp \
  core/fxcrt/fx_random.cpp \
  core/fxcrt/fx_stream.cpp \
  core/fxcrt/fx_string.cpp \
  core/fxcrt/fx_system.cpp \
  core/fxcrt/fx_unicode.cpp \
  core/fxcrt/mapped_data_bytes.cpp \
  core/fxcrt/observed_ptr.cpp \
  core/fxcrt/string_data_template.cpp \
  core/fxcrt/string_template.cpp \
  core/fxcrt/widestring.cpp \
  core/fxcrt/widetext_buffer.cpp \
  core/fxcrt/xml/cfx_xmlchardata.cpp \
  core/fxcrt/xml/cfx_xmldocument.cpp \
  core/fxcrt/xml/cfx_xmlelement.cpp \
  core/fxcrt/xml/cfx_xmlinstruction.cpp \
  core/fxcrt/xml/cfx_xmlnode.cpp \
  core/fxcrt/xml/cfx_xmlparser.cpp \
  core/fxcrt/xml/cfx_xmltext.cpp

PDFIUM_GROUP_24_COMPILER := $(CXX)
PDFIUM_GROUP_24_DEFINES := '-D__STDC_CONSTANT_MACROS' '-D__STDC_FORMAT_MACROS' '-D_FORTIFY_SOURCE=2' '-DNDEBUG' '-DNVALGRIND' '-DDYNAMIC_ANNOTATIONS_ENABLED=0' '-DOPJ_STATIC' '-DPDF_ENABLE_BROTLI' '-DPDF_USE_AGG' '-DFT_CONFIG_MODULES_H="freetype-custom-config/ftmodule.h"' '-DFT_CONFIG_OPTIONS_H="freetype-custom-config/ftoption.h"' '-DU_USING_ICU_NAMESPACE=0' '-DU_ENABLE_DYLOAD=0' '-DUSE_CHROMIUM_ICU=1' '-DU_ENABLE_TRACING=1' '-DU_ENABLE_RESOURCE_TRACING=0' '-DU_STATIC_IMPLEMENTATION' '-DICU_UTIL_DATA_IMPL=ICU_UTIL_DATA_FILE'
PDFIUM_GROUP_24_INCLUDES := '-I$(PDFIUM_SOURCE)' '-I$(PDFIUM_SOURCE)/third_party/freetype/include' '-I$(PDFIUM_SOURCE)/third_party/freetype/src/include' '-I$(PDFIUM_SOURCE)/third_party/abseil-cpp' '-I$(PDFIUM_SOURCE)/third_party/icu/source/common' '-I$(PDFIUM_SOURCE)/third_party/icu/source/i18n' '-I$(PDFIUM_SOURCE)/third_party/harfbuzz/src/src' '-I$(PDFIUM_SOURCE)/third_party/harfbuzz'
PDFIUM_GROUP_24_SOURCES := \
  core/fpdfapi/edit/cpdf_creator.cpp \
  core/fpdfapi/edit/cpdf_font_util.cpp \
  core/fpdfapi/edit/cpdf_fontsubsetter.cpp \
  core/fpdfapi/edit/cpdf_npagetooneexporter.cpp \
  core/fpdfapi/edit/cpdf_pagecontentgenerator.cpp \
  core/fpdfapi/edit/cpdf_pagecontentmanager.cpp \
  core/fpdfapi/edit/cpdf_pageexporter.cpp \
  core/fpdfapi/edit/cpdf_pageorganizer.cpp \
  core/fpdfapi/edit/cpdf_stringarchivestream.cpp

PDFIUM_GROUP_25_COMPILER := $(CXX)
PDFIUM_GROUP_25_DEFINES := '-D__STDC_CONSTANT_MACROS' '-D__STDC_FORMAT_MACROS' '-D_FORTIFY_SOURCE=2' '-DNDEBUG' '-DNVALGRIND' '-DDYNAMIC_ANNOTATIONS_ENABLED=0' '-DOPJ_STATIC' '-DPDF_ENABLE_BROTLI' '-DPDF_USE_AGG' '-DFT_CONFIG_MODULES_H="freetype-custom-config/ftmodule.h"' '-DFT_CONFIG_OPTIONS_H="freetype-custom-config/ftoption.h"' '-DU_USING_ICU_NAMESPACE=0' '-DU_ENABLE_DYLOAD=0' '-DUSE_CHROMIUM_ICU=1' '-DU_ENABLE_TRACING=1' '-DU_ENABLE_RESOURCE_TRACING=0' '-DU_STATIC_IMPLEMENTATION' '-DICU_UTIL_DATA_IMPL=ICU_UTIL_DATA_FILE' '-DUSE_LIBJPEG_TURBO=1' '-DMANGLE_JPEG_NAMES'
PDFIUM_GROUP_25_INCLUDES := '-I$(PDFIUM_SOURCE)' '-I$(PDFIUM_SOURCE)/third_party/freetype/include' '-I$(PDFIUM_SOURCE)/third_party/freetype/src/include' '-I$(PDFIUM_SOURCE)/third_party/abseil-cpp' '-I$(PDFIUM_SOURCE)/third_party/icu/source/common' '-I$(PDFIUM_SOURCE)/third_party/icu/source/i18n' '-I$(PDFIUM_SOURCE)/third_party/zlib' '-I$(PDFIUM_SOURCE)/third_party/brotli/include' '-I$(PDFIUM_SOURCE)/third_party/libjpeg_turbo/src'
PDFIUM_GROUP_25_SOURCES := \
  core/fxcodec/basic/basicmodule.cpp \
  core/fxcodec/brotli/brotli_decoder.cpp \
  core/fxcodec/data_and_bytes_consumed.cpp \
  core/fxcodec/fax/faxmodule.cpp \
  core/fxcodec/flate/flatemodule.cpp \
  core/fxcodec/fx_codec.cpp \
  core/fxcodec/icc/icc_transform.cpp \
  core/fxcodec/jbig2/jbig2_arith_decoder.cpp \
  core/fxcodec/jbig2/jbig2_arith_int_decoder.cpp \
  core/fxcodec/jbig2/jbig2_bit_stream.cpp \
  core/fxcodec/jbig2/jbig2_context.cpp \
  core/fxcodec/jbig2/jbig2_decoder.cpp \
  core/fxcodec/jbig2/jbig2_document_context.cpp \
  core/fxcodec/jbig2/jbig2_grd_proc.cpp \
  core/fxcodec/jbig2/jbig2_grrd_proc.cpp \
  core/fxcodec/jbig2/jbig2_htrd_proc.cpp \
  core/fxcodec/jbig2/jbig2_huffman_decoder.cpp \
  core/fxcodec/jbig2/jbig2_huffman_table.cpp \
  core/fxcodec/jbig2/jbig2_image.cpp \
  core/fxcodec/jbig2/jbig2_pattern_dict.cpp \
  core/fxcodec/jbig2/jbig2_pdd_proc.cpp \
  core/fxcodec/jbig2/jbig2_sdd_proc.cpp \
  core/fxcodec/jbig2/jbig2_segment.cpp \
  core/fxcodec/jbig2/jbig2_symbol_dict.cpp \
  core/fxcodec/jbig2/jbig2_trd_proc.cpp \
  core/fxcodec/jpeg/jpegmodule.cpp \
  core/fxcodec/jpeg/libjpeg_scanline_decoder.cpp \
  core/fxcodec/jpx/cjpx_decoder.cpp \
  core/fxcodec/jpx/jpx_decode_utils.cpp \
  core/fxcodec/scanlinedecoder.cpp
