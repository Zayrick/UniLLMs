//
//  UserDefaultsBackedTestCase.swift
//  UniLLMsTests
//

import Foundation
import XCTest
@testable import UniLLMs

class UserDefaultsBackedTestCase: XCTestCase {
    var defaults: UserDefaults!

    private var suiteName: String!

    override func setUpWithError() throws {
        try super.setUpWithError()
        suiteName = "\(type(of: self)).\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDownWithError() throws {
        if let defaults, let suiteName {
            defaults.removePersistentDomain(forName: suiteName)
        }
        defaults = nil
        suiteName = nil
        try super.tearDownWithError()
    }
}
