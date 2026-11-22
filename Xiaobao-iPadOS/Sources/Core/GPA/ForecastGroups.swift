import Foundation
import CryptoKit

/// Summary of strictly published items. No withheld academic value is passed to the
/// calculator; a released zero is an observation, an absent or pending row is not.
struct ForecastSamples: Equatable {
    let count: Int
    let allNumeric: Bool
    let percentSum: Double?
    let excludesUnreleased: Bool

    init(released: [GradeMark?], excludesUnreleased: Bool) {
        count = released.count
        self.excludesUnreleased = excludesUnreleased
        allNumeric = released.allSatisfy { mark in
            guard case .numeric(let score, let max, _) = mark, score.isFinite, score >= 0 else { return false }
            return max.map { $0.isFinite && $0 > 0 && score <= $0 } ?? true
        }
        let values = released.compactMap { $0?.forecastPercentage }
        percentSum = values.count == released.count ? values.reduce(0, +) : nil
    }
}

extension GradeMark {
    var forecastPercentage: Double? {
        guard case .numeric(let earned, let possible?, _) = self, possible.isFinite, possible > 0,
              earned.isFinite, (0...possible).contains(earned) else { return nil }
        return earned / possible * 100
    }
}

/// A school category, including empty categories which have no expandable task row.
/// Its weight belongs to the whole category, never to an individual draft.
struct ForecastGroup: Identifiable, Equatable {
    let id, title: String
    let parentID: String?
    let weight: AssessmentWeight?
    let published: GradeMark?
    let hasItems: Bool
    var samples: ForecastSamples? = nil
    /// Schoolis numeric evaluation-project scores are percentages. Other sources
    /// must not claim that a number without a maximum is necessarily out of 100.
    var reportedPercentage: Double? = nil
}

struct ForecastGroups: Equatable {
    let options: [ForecastGroup]
    let supportsNumericForecast: Bool
    private let byID: [String: ForecastGroup]
    private let anchorByID: [String: String]
    private let idsByAnchor: [String: [String]]

    init(_ options: [ForecastGroup] = [], supportsNumericForecast: Bool = true) {
        self.options = options
        self.supportsNumericForecast = supportsNumericForecast
        let lookup = Dictionary(options.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        byID = lookup
        var anchors: [String: String] = [:]
        var identifiers: [String: [String]] = [:]
        for group in options {
            var lineage = [group.title], parent = group.parentID, seen = Set([group.id])
            while let id = parent, let node = lookup[id], seen.insert(id).inserted {
                lineage.append(node.title)
                parent = node.parentID
            }
            guard parent == nil, let bytes = try? JSONEncoder().encode(Array(lineage.reversed())) else { continue }
            let key = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
            anchors[group.id] = key
            identifiers[key, default: []].append(group.id)
        }
        anchorByID = anchors
        idsByAnchor = identifiers
    }

    subscript(_ id: String?) -> ForecastGroup? { id.flatMap { byID[$0] } }
    var hasUniqueIDs: Bool { byID.count == options.count }

    func isLeaf(_ id: String) -> Bool { !options.contains { $0.parentID == id } }

    /// Source IDs can be positional. Never silently move a saved forecast to
    /// a different group after refresh, or choose between two identical labels.
    func anchor(for id: String?) -> String? { id.flatMap { anchorByID[$0] } }
    func id(for forecast: AssessmentForecast) -> String? {
        guard let anchor = forecast.groupAnchor else { return forecast.groupID }
        guard let candidates = idsByAnchor[anchor], candidates.count == 1 else { return nil }
        return candidates.first
    }

    func courseShare(of group: ForecastGroup) -> Double? {
        var current = group, seen: Set<String> = [], share = 1.0
        while seen.insert(current.id).inserted, let weight = current.weight {
            share *= weight.fraction
            if weight.scope == .course { return current.parentID == nil ? share : nil }
            guard let parent = self[current.parentID] else { return nil }
            current = parent
        }
        return nil
    }
}
