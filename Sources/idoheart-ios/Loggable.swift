//
//  Loggable.swift
//  IDoHeart
//
//  Created by idoheart on 22/1/2025.
//  Copyright © 2025 3 Cups Pty Ltd. All rights reserved.
//


import Foundation
import OSLog

protocol Loggable {
    init(subsystem: String, category: String, silenced: Bool)
    func debug(_ string: String)
    func info(_ string: String)
    func error(_ string: String)
}

/// wrapper that can have a nil logger to shut up logging.
/// USAGE:
/// fileprivate let localLogger = LoggerWrapper(silence: true) // silence logging
struct LoggerWrapper: Loggable {
    var logger: Logger? = nil
    init(subsystem: String, category: String, silenced: Bool = false) {
        if !silenced {
            self.logger = Logger(subsystem: subsystem, category: category)
        }
    }
    func debug(_ string: String) {
        if let logger = logger {
            logger.debug("\(string, privacy: .public)")
        }
    }
    func info(_ string: String) {
        logger?.info("\(string, privacy: .public)")
    }
    func error(_ string: String) {
        logger?.error("\(string, privacy: .public)")
    }
}

