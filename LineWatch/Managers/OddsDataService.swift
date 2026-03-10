//
//  OddsDataService.swift
//  LineWatch
//
//  Created by Steven Nguyen on 3/9/26.
//

import Foundation

@Observable
class OddsDataService {
    var eventsBySport: [SportCategory: [ResponseBody]] = [:]
    var isLoading = false
    var error: Error?

    private let linesManager = LinesManager()

    // Load from bundled JSON files (no API calls)
    func loadLocalData() {
        for sport in SportCategory.allCases {
            let events: [ResponseBody] = loadFromBundle(sport.localFileName)
            eventsBySport[sport] = events
        }
    }

    // Fetch from API for a single sport and cache locally
    func fetchAndCache(sport: SportCategory) async {
        isLoading = true
        defer { isLoading = false }

        do {
            let events = try await linesManager.getOdds(for: sport)
            eventsBySport[sport] = events
            saveToDocuments(events, filename: "\(sport.localFileName).json")
        } catch {
            self.error = error
            // Fall back to local data
            eventsBySport[sport] = loadFromBundle(sport.localFileName)
        }
    }

    // Fetch all sports from API
    func fetchAndCacheAll() async {
        isLoading = true
        defer { isLoading = false }

        for sport in SportCategory.allCases {
            do {
                let events = try await linesManager.getOdds(for: sport)
                eventsBySport[sport] = events
                saveToDocuments(events, filename: "\(sport.localFileName).json")
            } catch {
                self.error = error
                eventsBySport[sport] = loadFromBundle(sport.localFileName)
            }
        }
    }

    func events(for sport: SportCategory) -> [ResponseBody] {
        eventsBySport[sport] ?? []
    }

    // MARK: - Private Helpers

    private func saveToDocuments(_ events: [ResponseBody], filename: String) {
        guard let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.appendingPathComponent(filename) else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        if let data = try? encoder.encode(events) {
            try? data.write(to: url)
        }
    }

    private func loadFromBundle(_ filename: String) -> [ResponseBody] {
        guard let url = Bundle.main.url(forResource: filename, withExtension: "json") else {
            return []
        }
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([ResponseBody].self, from: data)) ?? []
    }
}
