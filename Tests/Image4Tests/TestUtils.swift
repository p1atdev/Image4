import Foundation
import Testing

func loadResource(name: String) throws -> Data {
    guard let url = Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "bin") else {
        fatalError("Resource \(name) not found")
    }
    return try Data(contentsOf: url)
}
