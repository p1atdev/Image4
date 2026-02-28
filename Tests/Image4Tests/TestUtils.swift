import Foundation
import Testing

func loadResource(name: String) throws -> Data {
    guard let url = Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "bin") else {
        fatalError("Resource \(name) not found")
    }
    return try Data(contentsOf: url)
}

enum TestResource {
    static var testPayload: Data {
        get throws { try loadResource(name: "test_payload") }
    }
    
    static var img4: Data {
        get throws { try loadResource(name: "IMG4") }
    }
    
    static var im4m: Data {
        get throws { try loadResource(name: "IM4M") }
    }
    
    static var im4p: Data {
        get throws { try loadResource(name: "IM4P") }
    }
    
    static var im4r: Data {
        get throws { try loadResource(name: "IM4R") }
    }

    // Remote resources
    static var decLZSSIM4P: Data {
        get async throws { try await IPSWResource.decLZSSIM4P }
    }

    static var encLZSSIM4P: Data {
        get async throws { try await IPSWResource.encLZSSIM4P }
    }

    static var decLZFSEIM4P: Data {
        get async throws { try await IPSWResource.decLZFSEIM4P }
    }

    static var encLZFSEIM4P: Data {
        get async throws { try await IPSWResource.encLZFSEIM4P }
    }

    static var paypIM4P: Data {
        get async throws { try await IPSWResource.paypIM4P }
    }
}
