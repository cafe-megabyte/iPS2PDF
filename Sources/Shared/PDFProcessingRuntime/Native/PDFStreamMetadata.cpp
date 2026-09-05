#include "PDFStreamMetadata.h"
#include "PDFImageMetadata.h"
#include "PDFBinaryImageMetadata.h"

#include <algorithm>
#include <span>
#include <stdexcept>
#include <string>
#include <vector>

namespace ips2pdf {
namespace {

using Object = QPDFObjectHandle;

std::vector<Object> filters(Object stream) {
    if (!stream.isStream()) return {};
    auto value = stream.getDict().getKey("/Filter");
    if (value.isName()) return {value};
    if (value.isArray()) return value.getArrayAsVector();
    return {};
}

bool dct(Object filter) {
    return filter.isNameAndEquals("/DCTDecode") || filter.isNameAndEquals("/DCT");
}

} // namespace

bool isJPEGStream(Object stream) {
    auto chain = filters(stream);
    return std::any_of(chain.begin(), chain.end(), dct);
}

bool cleanJPEGStream(QPDF& owner, Object stream, bool preserveICC) {
    auto chain = filters(stream);
    if (chain.empty() || !dct(chain.back()) ||
        std::count_if(chain.begin(), chain.end(), dct) != 1) {
        throw std::runtime_error("Unsupported JPEG filter sequence");
    }
    auto dictionary = stream.getDict();
    auto parameters = dictionary.getKey("/DecodeParms");
    std::vector<Object> parameter_chain(chain.size(), Object::newNull());
    if (parameters.isArray()) {
        if (parameters.getArrayNItems() != static_cast<int>(chain.size()))
            throw std::runtime_error("JPEG filter parameters do not match its filters");
        parameter_chain = parameters.getArrayAsVector();
    } else if (!parameters.isNull()) {
        if (chain.size() != 1 || !parameters.isDictionary())
            throw std::runtime_error("Ambiguous JPEG filter parameters");
        parameter_chain[0] = parameters;
    }
    // qpdf supplies decrypted raw bytes. Decode only the outer lossless
    // transport filters, leaving the terminal JPEG codestream untouched.
    auto raw = stream.getRawStreamData();
    auto encoded = raw;
    if (chain.size() > 1) {
        std::vector<Object> outer, outer_parameters;
        for (size_t i = 0; i + 1 < chain.size(); ++i) {
            if (chain[i].isNameAndEquals("/Crypt")) {
                // Decryption has already been applied by getRawStreamData.
                if (i != 0) throw std::runtime_error("Invalid Crypt filter ordering");
                continue;
            }
            outer.push_back(chain[i]);
            outer_parameters.push_back(parameter_chain[i]);
        }
        if (!outer.empty()) {
            auto transport = owner.newStream(raw);
            transport.getDict().replaceKey("/Filter", Object::newArray(outer));
            transport.getDict().replaceKey("/DecodeParms", Object::newArray(outer_parameters));
            encoded = transport.getStreamData(qpdf_dl_specialized);
            // The temporary stream stays unreferenced and is omitted by the
            // full writer, even if the original PDF used object streams.
        }
    }
    std::span<const uint8_t> input(encoded->getBuffer(), encoded->getSize());
    auto cleaned = removeJPEGMetadata(input, preserveICC);
    bool same = cleaned.size() == input.size() && std::equal(cleaned.begin(), cleaned.end(), input.begin());
    if (same && chain.size() == 1) return false;
    stream.replaceStreamData(std::string(cleaned.begin(), cleaned.end()), Object::newName("/DCTDecode"),
                             parameter_chain.back());
    // Do not let a later generalized stream optimization decode this image.
    stream.setFilterOnWrite(false);
    return true;
}

bool cleanBinaryImageStream(QPDF& owner, Object stream) {
    auto chain = filters(stream);
    const bool jpx = std::any_of(chain.begin(), chain.end(), [](Object filter) { return filter.isNameAndEquals("/JPXDecode"); });
    const bool jbig = std::any_of(chain.begin(), chain.end(), [](Object filter) { return filter.isNameAndEquals("/JBIG2Decode"); });
    if (!jpx && !jbig) return false;
    const std::string terminal = jpx ? "/JPXDecode" : "/JBIG2Decode";
    if ((jpx && jbig) || chain.empty() || !chain.back().isNameAndEquals(terminal))
        throw std::runtime_error("Unsupported binary image filter sequence");
    auto parameters = stream.getDict().getKey("/DecodeParms");
    std::vector<Object> parameterChain(chain.size(), Object::newNull());
    if (parameters.isArray()) {
        if (parameters.getArrayNItems() != static_cast<int>(chain.size())) throw std::runtime_error("Invalid image filter parameters");
        parameterChain = parameters.getArrayAsVector();
    } else if (!parameters.isNull()) {
        if (chain.size() != 1 || !parameters.isDictionary()) throw std::runtime_error("Invalid image filter parameters");
        parameterChain[0] = parameters;
    }
    auto encoded = stream.getRawStreamData();
    if (chain.size() > 1) {
        std::vector<Object> outer, outerParameters;
        for (size_t i = 0; i + 1 < chain.size(); ++i) {
            if (chain[i].isNameAndEquals("/Crypt") && i == 0) continue;
            if (chain[i].isNameAndEquals(terminal)) throw std::runtime_error("Repeated binary image filter");
            outer.push_back(chain[i]); outerParameters.push_back(parameterChain[i]);
        }
        if (!outer.empty()) {
            auto transport = owner.newStream(encoded);
            transport.getDict().replaceKey("/Filter", Object::newArray(outer));
            transport.getDict().replaceKey("/DecodeParms", Object::newArray(outerParameters));
            encoded = transport.getStreamData(qpdf_dl_specialized);
        }
    }
    const std::span<const uint8_t> input(encoded->getBuffer(), encoded->getSize());
    auto cleaned = jpx ? removeJPEG2000Metadata(input) : removeJBIG2Metadata(input);
    bool changed = chain.size() != 1 || cleaned.size() != input.size() || !std::equal(cleaned.begin(), cleaned.end(), input.begin());
    if (changed) {
        stream.replaceStreamData(std::string(cleaned.begin(), cleaned.end()), Object::newName(terminal), parameterChain.back());
        stream.setFilterOnWrite(false);
    }
    if (jbig && parameterChain.back().isDictionary()) {
        auto globals = parameterChain.back().getKey("/JBIG2Globals");
        if (!globals.isNull()) {
            if (!globals.isStream()) throw std::runtime_error("Invalid JBIG2 global segment stream");
            const auto bytes = globals.getStreamData(qpdf_dl_generalized);
            const auto sanitized = removeJBIG2Metadata(std::span(bytes->getBuffer(), bytes->getSize()));
            if (sanitized.size() != bytes->getSize() || !std::equal(sanitized.begin(), sanitized.end(), bytes->getBuffer())) {
                globals.replaceStreamData(std::string(sanitized.begin(), sanitized.end()), Object::newNull(), Object::newNull());
                changed = true;
            }
        }
    }
    return changed;
}

} // namespace ips2pdf
