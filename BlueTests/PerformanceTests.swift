import Foundation
import Testing

@testable import Blue

struct QueryPerformanceTests {
    @Test func measureSearchAndSortWithNormalAndStressData() {
        for count in [27, 10_000] {
            let collection = UUID()
            let records = (0..<count).map {
                Record(
                    collectionID: collection, title: String(format: "Item %05d", $0),
                    values: ["rating": .number(Double($0 % 11))])
            }
            let query = CollectionQuery(search: "Item 0", sortField: "rating", ascending: false)
            let clock = ContinuousClock()
            var samples: [Double] = []
            for _ in 0..<10 {
                let start = clock.now
                let result = query.apply(to: records, fields: [], locale: Locale(identifier: "en_US"))
                let duration = start.duration(to: clock.now).components
                samples.append(Double(duration.seconds) * 1000 + Double(duration.attoseconds) / 1e15)
                #expect(!result.isEmpty)
            }
            print("QUERY_BASELINE count=\(count) median_ms=\(samples.sorted()[5]) max_ms=\(samples.max() ?? 0)")
        }
    }
}
