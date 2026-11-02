import MapKit
import SwiftUI

/// Plan G4: free-text place search with MapKit. No location permission is
/// requested; the person types a place and picks a result.
nonisolated struct PlaceChoice: Hashable, Sendable {
    let name: String
    let latitude: Double?
    let longitude: Double?
}

struct LocationSearchView: View {
    @Binding var selection: PlaceChoice?
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [MKMapItem] = []
    @State private var searching = false
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            List {
                if !query.trimmingCharacters(in: .whitespaces).isEmpty {
                    Button {
                        selection = PlaceChoice(name: query.trimmingCharacters(in: .whitespaces), latitude: nil, longitude: nil)
                        dismiss()
                    } label: {
                        Label("Use \"\(query.trimmingCharacters(in: .whitespaces))\"", systemImage: "text.cursor")
                    }
                }
                ForEach(results, id: \.self) { item in
                    Button {
                        let c = item.placemark.coordinate
                        selection = PlaceChoice(name: item.name ?? query, latitude: c.latitude, longitude: c.longitude)
                        dismiss()
                    } label: {
                        VStack(alignment: .leading) {
                            Text(item.name ?? "Place").font(.body)
                            if let locality = [item.placemark.locality, item.placemark.administrativeArea].compactMap({ $0 }).joined(separator: ", ").nilIfEmpty {
                                Text(locality).font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                if searching { ProgressView() }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search for a place")
            .onChange(of: query) { _, new in
                searchTask?.cancel()
                let text = new.trimmingCharacters(in: .whitespaces)
                guard text.count >= 2 else { results = []; return }
                searchTask = Task {
                    try? await Task.sleep(for: .milliseconds(350))
                    guard !Task.isCancelled else { return }
                    await search(text)
                }
            }
            .navigationTitle("Location")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }

    private func search(_ text: String) async {
        searching = true
        defer { searching = false }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = text
        request.resultTypes = [.pointOfInterest, .address]
        let response = try? await MKLocalSearch(request: request).start()
        guard !Task.isCancelled else { return }
        results = Array((response?.mapItems ?? []).prefix(12))
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
