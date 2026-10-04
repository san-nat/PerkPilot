import SwiftUI

/// Phase 2 stub. The discovery feed (72-hour Reddit / issuer / press scans)
/// runs on a server; until it ships, this tab explains what's coming instead
/// of showing an empty list with no context.
struct NewsView: View {
    private let service: DiscoveryProviding = DiscoveryServiceStub()
    @State private var items: [DiscoveryItem] = []

    var body: some View {
        NavigationStack {
            Group {
                if items.isEmpty {
                    ContentUnavailableView {
                        Label("Discovery feed coming soon", systemImage: "newspaper")
                    } description: {
                        Text("Every 72 hours a behind-the-scenes scan will check Reddit, issuer pages, and points press for new hidden benefits, credit changes, and enrollment updates for your cards. New finds land here for your review — nothing is ever added to your benefits automatically.")
                    } actions: {
                        Text("Last checked: not yet running")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    List(items) { item in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(item.title).font(.headline)
                            Text(item.summary).font(.body)
                            HStack {
                                Text(item.grade.capitalized)
                                Text("•")
                                Text(item.sourceName)
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                    .refreshable { await load() }
                }
            }
            .navigationTitle("News")
            .task { await load() }
        }
    }

    private func load() async {
        items = (try? await service.fetchItems(after: nil).items) ?? []
    }
}

#Preview {
    NewsView()
}
