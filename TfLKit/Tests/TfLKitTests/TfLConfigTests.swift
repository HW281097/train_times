import XCTest
@testable import TfLKit

final class TfLConfigTests: XCTestCase {
    private func writeConfig(_ json: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "leaboard-tfl-test-\(UUID().uuidString).json")
        try Data(json.utf8).write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    func testLoadsTflBlockFromFile() throws {
        let url = try writeConfig("""
        {
          "apiKey": "darwin-key",
          "tfl": {
            "appKey": "tfl-key",
            "directionA": { "id": "490009131W", "label": "Towards Hackney" },
            "directionB": { "id": "490009131E", "label": "Towards Walthamstow" }
          }
        }
        """)
        let config = try TfLConfig.load(from: url)
        XCTAssertEqual(config.appKey, "tfl-key")
        XCTAssertEqual(config.directionA, TfLConfig.Stop(id: "490009131W", label: "Towards Hackney"))
        XCTAssertEqual(config.directionB, TfLConfig.Stop(id: "490009131E", label: "Towards Walthamstow"))
        XCTAssertEqual(config.stops.count, 2)
    }

    func testAppKeyIsOptional() throws {
        let url = try writeConfig("""
        {
          "tfl": {
            "directionA": { "id": "490009131W", "label": "A" },
            "directionB": { "id": "490009131E", "label": "B" }
          }
        }
        """)
        let config = try TfLConfig.load(from: url)
        XCTAssertNil(config.appKey)
    }

    func testPlaceholderAppKeyBecomesNil() throws {
        let url = try writeConfig("""
        {
          "tfl": {
            "appKey": "YOUR_TFL_APP_KEY",
            "directionA": { "id": "490009131W", "label": "A" },
            "directionB": { "id": "490009131E", "label": "B" }
          }
        }
        """)
        XCTAssertNil(try TfLConfig.load(from: url).appKey)
    }

    func testMissingTflBlockThrowsMissingConfiguration() throws {
        let url = try writeConfig(#"{ "apiKey": "darwin-only" }"#)
        XCTAssertThrowsError(try TfLConfig.load(from: url)) { error in
            guard case TfLError.missingConfiguration = error else {
                return XCTFail("Expected .missingConfiguration, got \(error)")
            }
        }
    }

    func testPlaceholderStopIdsThrowInvalid() throws {
        let url = try writeConfig("""
        {
          "tfl": {
            "directionA": { "id": "490…", "label": "A" },
            "directionB": { "id": "490…", "label": "B" }
          }
        }
        """)
        XCTAssertThrowsError(try TfLConfig.load(from: url)) { error in
            guard case TfLError.invalidConfiguration = error else {
                return XCTFail("Expected .invalidConfiguration, got \(error)")
            }
        }
    }

    func testEnvironmentOverridesTakePrecedence() throws {
        let config = try TfLConfig.load(environment: [
            "TFL_APP_KEY": "env-key",
            "TFL_STOP_A_ID": "490AAA", "TFL_STOP_A_LABEL": "Towards Hackney",
            "TFL_STOP_B_ID": "490BBB", "TFL_STOP_B_LABEL": "Towards Walthamstow",
        ])
        XCTAssertEqual(config.appKey, "env-key")
        XCTAssertEqual(config.directionA.id, "490AAA")
        XCTAssertEqual(config.directionB.label, "Towards Walthamstow")
    }
}
