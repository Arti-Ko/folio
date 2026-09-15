import Foundation

/// Номер версии вида 1.2.3. Префикс «v» и хвост после «-» (1.2.0-beta) отбрасываются.
public struct AppVersion: Comparable, Hashable, CustomStringConvertible, Sendable {
    public let components: [Int]

    public init?(_ string: String) {
        var trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.first == "v" || trimmed.first == "V" {
            trimmed.removeFirst()
        }
        let core = trimmed.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false).first ?? ""
        let parts = core.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
        guard !parts.isEmpty, parts.allSatisfy({ $0 != nil }) else { return nil }
        components = parts.compactMap { $0 }
    }

    /// Версия запущенного бандла; nil, если программа запущена не из .app.
    public static var current: AppVersion? {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String).flatMap(AppVersion.init)
    }

    public var description: String {
        components.map(String.init).joined(separator: ".")
    }

    public static func == (lhs: AppVersion, rhs: AppVersion) -> Bool {
        compare(lhs, rhs) == 0
    }

    public static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        compare(lhs, rhs) < 0
    }

    /// 1.2 и 1.2.0 равны, поэтому хвостовые нули в хэш не входят.
    public func hash(into hasher: inout Hasher) {
        var significant = components
        while significant.last == 0 {
            significant.removeLast()
        }
        hasher.combine(significant)
    }

    private static func compare(_ lhs: AppVersion, _ rhs: AppVersion) -> Int {
        let count = max(lhs.components.count, rhs.components.count)
        for index in 0..<count {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right {
                return left < right ? -1 : 1
            }
        }
        return 0
    }
}
