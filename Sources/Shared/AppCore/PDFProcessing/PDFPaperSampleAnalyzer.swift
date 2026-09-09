import CoreGraphics
import Foundation

enum PDFPaperSampleAnalyzer {
    static func analyze(_ image: CGImage, pageIndex: Int,
                        normalizedPoint: CGPoint) -> PDFPaperSample? {
        guard image.width > 0, image.height > 0 else { return nil }
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        var rgba = [UInt8](repeating: 0, count: image.width * image.height * 4)
        guard let context = CGContext(
            data: &rgba, width: image.width, height: image.height,
            bitsPerComponent: 8, bytesPerRow: image.width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue |
                CGBitmapInfo.byteOrder32Big.rawValue
        ) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))

        var pixels: [(red: Double, green: Double, blue: Double, luminance: Double)] = []
        let strideValue = max(1, Int(ceil(sqrt(Double(image.width * image.height) / 4_096))))
        for y in stride(from: 0, to: image.height, by: strideValue) {
            for x in stride(from: 0, to: image.width, by: strideValue) {
                let offset = (y * image.width + x) * 4
                guard rgba[offset + 3] >= 240 else { continue }
                let red = Double(rgba[offset])
                let green = Double(rgba[offset + 1])
                let blue = Double(rgba[offset + 2])
                let luminance = 0.2126 * red + 0.7152 * green + 0.0722 * blue
                pixels.append((red, green, blue, luminance))
            }
        }
        guard !pixels.isEmpty else { return nil }

        // A paper-area tap may include text. Discard its darkest samples before
        // learning the area's color modes, rather than averaging ink into the
        // paper reference.
        let sortedLuminance = pixels.map(\.luminance).sorted()
        let lowerQuintile = sortedLuminance[sortedLuminance.count / 5]
        let cutoff = max(64, lowerQuintile)
        let retained = pixels.filter { $0.luminance >= cutoff }
        let input = retained.isEmpty ? pixels : retained

        func chromaticity(_ pixel: (red: Double, green: Double, blue: Double,
                                     luminance: Double)) -> SIMD3<Double> {
            let sum = max(1, pixel.red + pixel.green + pixel.blue)
            return SIMD3(pixel.red / sum, pixel.green / sum, pixel.blue / sum)
        }
        let points = input.map(chromaticity)
        let clusterCount = min(3, points.count)
        var centers = [points[0]]
        while centers.count < clusterCount {
            let candidate = points.max { left, right in
                centers.map { squaredDistance(left, $0) }.min()! <
                    centers.map { squaredDistance(right, $0) }.min()!
            }!
            centers.append(candidate)
        }
        var assignments = [Int](repeating: 0, count: points.count)
        for _ in 0..<10 {
            for index in points.indices {
                assignments[index] = centers.indices.min {
                    squaredDistance(points[index], centers[$0]) <
                        squaredDistance(points[index], centers[$1])
                }!
            }
            for cluster in centers.indices {
                let members = points.indices.filter { assignments[$0] == cluster }
                guard !members.isEmpty else { continue }
                centers[cluster] = members.reduce(SIMD3<Double>(repeating: 0)) {
                    $0 + points[$1]
                } / Double(members.count)
            }
        }

        let minimumMembers = max(1, points.count / 25)
        let colors = centers.indices.compactMap { cluster -> (Int, PDFPaperSample.Color)? in
            let members = input.indices.filter { assignments[$0] == cluster }
            guard members.count >= minimumMembers else { return nil }
            let totals = members.reduce(SIMD3<Double>(repeating: 0)) { partial, index in
                partial + SIMD3(input[index].red, input[index].green, input[index].blue)
            } / Double(members.count)
            return (members.count, PDFPaperSample.Color(
                red: Int(totals.x.rounded()), green: Int(totals.y.rounded()),
                blue: Int(totals.z.rounded())
            ))
        }
        .sorted { $0.0 > $1.0 }
        .map(\.1)
        guard !colors.isEmpty else { return nil }
        return PDFPaperSample(
            pageIndex: pageIndex,
            normalizedX: min(1, max(0, normalizedPoint.x)),
            normalizedY: min(1, max(0, normalizedPoint.y)),
            colors: Array(colors.prefix(3))
        )
    }

    private static func squaredDistance(_ left: SIMD3<Double>,
                                        _ right: SIMD3<Double>) -> Double {
        let difference = left - right
        return difference.x * difference.x + difference.y * difference.y +
            difference.z * difference.z
    }
}
