import Foundation
@testable import FileMorrow

enum TestProfiles {
    static let general: OrganizationProfile = {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = root.appending(path: "Configuration/default-profile.json")
        let data = try! Data(contentsOf: url)
        return try! JSONDecoder().decode(OrganizationProfile.self, from: data)
    }()
}
