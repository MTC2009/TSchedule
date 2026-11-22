import Foundation

/// A hypothetical assessment, separate from the school's grade records.
struct AssessmentForecast: Identifiable, Equatable, Codable {
    let id: UUID
    let name: String?
    let groupID: String?
    let groupAnchor: String?
    let mark: Double

    init(id: UUID = UUID(), name: String? = nil, groupID: String? = nil, groupAnchor: String? = nil, mark: Double) throws {
        guard mark.isFinite, (0...100).contains(mark) else { throw GradeError.invalidScore }
        let name = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.id = id
        self.name = name.flatMap { $0.isEmpty ? nil : $0 }
        self.groupID = groupID
        self.groupAnchor = groupAnchor
        self.mark = mark
    }
}

/// Local what-if, using OpenGCalc's mathematical model: equally counted task percentages
/// within a leaf, then the relative published weights of groups with scores. No browser
/// extension code or school access is needed. Nested weights are local to their parent.
enum CourseForecast {
    enum Result: Equatable {
        case noEstimates, missingCourseTotal, missingGroup, missingWeight, unknownAllocation
        case missingScoreScale, missingCount, selectLeaf, nonNumericCourse
        case estimated(Double)
    }

    struct Subtotal: Identifiable {
        let id, title: String
        let percentage: Double
    }
    struct Projection {
        let result: Result
        let subtotals: [Subtotal]
        var partialSubtotals: [Subtotal] {
            if case .estimated = result { return [] }
            return subtotals
        }
        var percentage: Double? {
            if case .estimated(let value) = result { return value }
            return nil
        }
    }

    private enum Value {
        case score(Double), empty, unavailable(Result)
    }

    static func calculate(current: Double?, groups: ForecastGroups, estimates: [AssessmentForecast]) -> Result {
        project(current: current, groups: groups, estimates: estimates).result
    }

    static func project(current: Double?, groups: ForecastGroups, estimates: [AssessmentForecast]) -> Projection {
        func failure(_ result: Result) -> Projection { .init(result: result, subtotals: []) }
        guard !estimates.isEmpty else { return failure(.noEstimates) }
        guard groups.supportsNumericForecast else { return failure(.nonNumericCourse) }
        guard groups.hasUniqueIDs else { return failure(.unknownAllocation) }
        let children = Dictionary(grouping: groups.options, by: \.parentID)
        guard !groups.options.contains(where: { $0.parentID != nil && groups[$0.parentID] == nil }) else { return failure(.missingWeight) }
        var reachable = Set<String>(), queue = children[nil] ?? []
        while let node = queue.popLast(), reachable.insert(node.id).inserted { queue += children[node.id] ?? [] }
        guard reachable.count == groups.options.count else { return failure(.unknownAllocation) }
        var drafts: [String: [Double]] = [:], touched = Set<String>()
        for draft in estimates {
            guard let group = groups[groups.id(for: draft)] else { return failure(.missingGroup) }
            guard children[group.id] == nil else { return failure(.selectLeaf) }
            drafts[group.id, default: []].append(draft.mark)
            // Positional IDs may be arbitrary in a test service; terminate on an orphan or cycle.
            var node: ForecastGroup? = group, path = Set<String>()
            while let n = node {
                guard path.insert(n.id).inserted else { return failure(.unknownAllocation) }
                touched.insert(n.id)
                if let parent = n.parentID, groups[parent] == nil { return failure(.missingWeight) }
                node = groups[n.parentID]
            }
        }
        func aggregate(_ group: ForecastGroup, trustUnscaled: Bool) -> Double? {
            if let value = group.reportedPercentage, value.isFinite, (0...100).contains(value) { return value }
            if let value = group.published?.forecastPercentage { return value }
            if trustUnscaled, case .numeric(let raw, nil, _) = group.published, (0...100).contains(raw) { return raw }
            return nil
        }
        func leaf(_ group: ForecastGroup, with additions: [Double], trustUnscaled: Bool) -> Value {
            let graded = aggregate(group, trustUnscaled: trustUnscaled)
            if additions.isEmpty, let graded { return .score(graded) }
            if let samples = group.samples, samples.count > 0 {
                guard samples.allNumeric else { return .unavailable(.missingScoreScale) }
                // A reported category average can anchor known contributors. If there are
                // also withheld rows, use only visible normalized marks; do not back-solve them.
                let sum: Double?
                if let graded, !samples.excludesUnreleased { sum = graded * Double(samples.count) }
                else { sum = samples.percentSum }
                guard let sum else { return .unavailable(.missingScoreScale) }
                return .score((sum + additions.reduce(0, +)) / Double(samples.count + additions.count))
            }
            if !additions.isEmpty, group.samples?.count == 0 {
                // OpenGCalc starts with the hypothetical item when its group has
                // no graded rows to count, even if an aggregate is available.
                return .score(additions.reduce(0, +) / Double(additions.count))
            }
            if group.published != nil || (group.samples == nil && group.hasItems) {
                // A subtotal without a contributor count cannot be mixed with an extra task.
                return .unavailable(additions.isEmpty ? .unknownAllocation : .missingCount)
            }
            if !additions.isEmpty { return .score(additions.reduce(0, +) / Double(additions.count)) }
            return group.samples == nil ? .unavailable(.unknownAllocation) : .empty
        }

        let subtotals = groups.options.compactMap { group -> Subtotal? in
            guard let marks = drafts[group.id], case .score(let pct) = leaf(group, with: marks, trustUnscaled: false) else { return nil }
            return .init(id: group.id, title: group.title, percentage: pct)
        }
        let roots = children[nil] ?? []
        let current = current.flatMap { $0.isFinite && (0...100).contains($0) ? $0 : nil }

        func weighted(_ nodes: [ForecastGroup], scope: AssessmentWeight.Scope, includeDrafts: Bool, trustUnscaled: Bool) -> Value {
            guard !nodes.isEmpty else { return .empty }
            var numerator = 0.0, denominator = 0.0, declared = 0.0
            for group in nodes {
                let share = group.weight
                if let share {
                    guard share.scope == scope else { return .unavailable(.missingWeight) }
                    declared += share.fraction
                    if share.fraction == 0 { continue }
                }
                let value: Value
                if (!includeDrafts || !touched.contains(group.id)), let published = aggregate(group, trustUnscaled: trustUnscaled) {
                    value = .score(published)
                } else if let branches = children[group.id] {
                    if group.hasItems && (group.samples?.count ?? 1) > 0 { return .unavailable(.unknownAllocation) }
                    value = weighted(branches, scope: .group, includeDrafts: includeDrafts, trustUnscaled: trustUnscaled)
                } else {
                    // A draft target that had no previous mark is inactive in the baseline.
                    if !includeDrafts && drafts[group.id] != nil && group.published == nil && !group.hasItems { value = .empty }
                    else { value = leaf(group, with: includeDrafts ? drafts[group.id] ?? [] : [], trustUnscaled: trustUnscaled) }
                }
                if case .empty = value { continue } // An unscored group needs neither a score nor a weight.
                guard let share else { return .unavailable(.missingWeight) }
                switch value {
                case .score(let percentage): numerator += share.fraction * percentage; denominator += share.fraction
                case .empty: break
                case .unavailable: return value
                }
            }
            // A partial generic snapshot does not prove the full category roster. Schoolis
            // supplies a full group tree; its active weights can be normalized even when rounded.
            if nodes.contains(where: { $0.samples == nil }) && abs(declared - 1) > 1e-8 { return .unavailable(.unknownAllocation) }
            return denominator > 0 ? .score(numerator / denominator) : .empty
        }

        let result: Result
        if let current, drafts.keys.allSatisfy({ id in groups[id].flatMap(groups.courseShare(of:)) == 0 }) {
            result = .estimated(current)
        } else {
            // Some non-portal snapshots contain bare numbers with no unit. Reuse those
            // only if the unchanged baseline independently explains the published total.
            let hasUnscaled = groups.options.contains { group in
                if case .numeric(_, nil, _) = group.published { return group.reportedPercentage == nil }
                return false
            }
            var trustUnscaled = false
            if hasUnscaled, let current, case .score(let baseline) = weighted(roots, scope: .course, includeDrafts: false, trustUnscaled: true) {
                trustUnscaled = abs(baseline - current) < 1e-8
            }
            switch weighted(roots, scope: .course, includeDrafts: true, trustUnscaled: trustUnscaled) {
            case .score(let number): result = .estimated(min(100, max(0, number)))
            case .empty: result = .unknownAllocation
            case .unavailable(let reason):
                result = hasUnscaled && current == nil && reason == .unknownAllocation ? .missingCourseTotal : reason
            }
        }
        return .init(result: result, subtotals: subtotals)
    }
}
