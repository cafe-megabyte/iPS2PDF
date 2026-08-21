import Darwin

#if !ENHANCED_SECURITY_HELPER
struct OpenDescriptors {
    let input: Int32
    let output: Int32
    let joboptions: Int32
    let journal: Int32
    let allowTransparency: Bool
    let profileSelections: [ProfileSelection]
    let userProfiles: [OpenUserProfile]

    func closeAll() {
        ([input, output, joboptions, journal] + userProfiles.map(\.descriptor))
            .filter { $0 >= 0 }
            .forEach { Darwin.close($0) }
    }
}
#endif
