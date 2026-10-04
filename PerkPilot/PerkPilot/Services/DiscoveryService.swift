import Foundation

// MARK: - Phase 2 stub: discovery feed
//
// The 72-hour discovery pipeline (Reddit / issuer pages / points press) runs
// on a *server*, not in this app: iOS background execution cannot guarantee an
// exact 72-hour cadence, and provider API secrets must never ship in the app
// binary. This service layer defines the contract the Phase 2 implementation
// will satisfy. Until then the News tab shows a clean empty state.

/// A candidate finding from the discovery pipeline. Display-only: a discovery
/// item is NEVER auto-promoted into a benefit; promotion requires human review.
struct DiscoveryItem: Identifiable, Sendable {
    var id: String
    var title: String
    var summary: String
    var cardStableIds: [String]
    /// Evidence grade: "official", "corroborated", "community", "watch".
    var grade: String
    var sourceName: String
    var sourceURL: URL?
    var observedAt: Date
    /// Suggested action: "enroll", "use-before", "verify", "save", "none".
    var suggestedAction: String
}

protocol DiscoveryProviding: Sendable {
    /// New items since `cursor` (nil = latest page). Sorted newest-first.
    func fetchItems(after cursor: String?) async throws -> (items: [DiscoveryItem], nextCursor: String?)
    var lastCheckedAt: Date? { get }
}

/// Phase 1 implementation: always empty, lastCheckedAt nil.
/// Phase 2: replace with a network client hitting the catalog API's
/// GET /v1/discover endpoint (server owns the 72-hour schedule and secrets).
final class DiscoveryServiceStub: DiscoveryProviding, Sendable {
    var lastCheckedAt: Date? { nil }

    func fetchItems(after cursor: String?) async throws -> (items: [DiscoveryItem], nextCursor: String?) {
        // PHASE 2: perform HTTPS request, decode signed feed, return items.
        return ([], nil)
    }
}
