import Foundation

/// Both local catalogs have the same failure policy: bundled English fallback.
enum BundledCatalog {
    static func load<Value: Decodable>(_ name: String, fallback: Value) -> [String: Value] {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle.main
        #endif
        guard let url = bundle.url(forResource: name, withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let values = try? JSONDecoder().decode([String: Value].self, from: data) else { return ["en": fallback] }
        return values
    }
}
