# jpegli encoder/decoder and Highway runtime source lists.
JPEGLI_SOURCES := \
  lib/jpegli/adaptive_quantization.cc \
  lib/jpegli/bit_writer.cc \
  lib/jpegli/bitstream.cc \
  lib/jpegli/color_quantize.cc \
  lib/jpegli/color_transform.cc \
  lib/jpegli/common.cc \
  lib/jpegli/decode.cc \
  lib/jpegli/decode_marker.cc \
  lib/jpegli/decode_scan.cc \
  lib/jpegli/destination_manager.cc \
  lib/jpegli/downsample.cc \
  lib/jpegli/encode.cc \
  lib/jpegli/encode_finish.cc \
  lib/jpegli/encode_streaming.cc \
  lib/jpegli/entropy_coding.cc \
  lib/jpegli/error.cc \
  lib/jpegli/huffman.cc \
  lib/jpegli/idct.cc \
  lib/jpegli/input.cc \
  lib/jpegli/memory_manager.cc \
  lib/jpegli/quant.cc \
  lib/jpegli/render.cc \
  lib/jpegli/simd.cc \
  lib/jpegli/source_manager.cc \
  lib/jpegli/upsample.cc

HIGHWAY_SOURCES := \
  hwy/abort.cc \
  hwy/aligned_allocator.cc \
  hwy/nanobenchmark.cc \
  hwy/per_target.cc \
  hwy/print.cc \
  hwy/targets.cc \
  hwy/timer.cc
