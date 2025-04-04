//
//  IDoHeart.swift
//  IdoHeartSampleApp
//
//  Created by idoheart on 22/3/2025.
//  Copyright © 2025 3 Cups Pty Ltd. All rights reserved.
//

import Foundation

/// Referral model returned by backend and used to store in user defaults
public struct Referral: Codable, Sendable {
    var referralRefId: String // the document ref id
    public var usedCount: Int  // single use 0 or 1 
    public var code: String    // 32 bit hex
    public var createdAt: Date // local time not same as server side createdAt timestamp
    public var usedAt: Date? // local time not same as server side createdAt timestamp
}

/// SDK main functions to call the IDoHeart API.
/// Usage:
/// IDoHeart.shared.configure(apiKey: "abc...")
/// IDoHeart.shared.generateCode() // returns a new referral
/// IDoHeart.shared.useCode(code:)  // redeems the code
/// IDoHeart.shared.checkCode(code:) // returns a referral of nil if not valid
public class IDoHeart {
    @MainActor public static let shared = IDoHeart()
    public var apiKey: String? = nil
    private var logger = LoggerWrapper(
        subsystem: "IDoHeart.API",
        category: #file,
        silenced: false
    )
    
    /// this configures the shared singleton with an API key
    public func configure(apiKey: String, isLogging: Bool = true) {
        self.apiKey = apiKey
        self.logger = LoggerWrapper(
            subsystem: "IDoHeart.API",
            category: #file,
            silenced: !isLogging
        )
    }

    /// Async Task to create a referral code via API
    /// returns a Referral on success and nil if something went wrong
    @MainActor
    public func generateCode() async throws -> Referral? {
        guard let apiKeyString = apiKey else {
            logger.error("❌ Error: IDoHeart API key not set")
            throw APIError.noAPIKey
        }
        do {
            let referral = try await IDoHeartGenerateCode.postRequest(
                to: "https://idoheart.com/api/createReferral",
                apiKey: apiKeyString
            )
            logger.debug("document RefId: \(referral.referralRefId), code: \(referral.code)")
            return referral
        } catch APIError.invalidURL {
            logger.error("❌ Error: generateCode: Invalid URL")
            throw APIError.invalidURL
        } catch APIError.requestFailed(let statusCode) {
            logger.error("❌ Error: generateCode: Request failed with status code \(statusCode)")
            throw APIError.requestFailed(statusCode: statusCode)
        } catch APIError.decodingFailed {
            logger.error("❌ Error: generateCode: Failed to decode response")
            throw APIError.decodingFailed
        } catch {
            logger.error("❌ Unknown Error: generateCode: \(error)")
            throw error
        }
    }
    
    /// Async Task to use a referral code via API
    /// returns a `IDoHeartUseCode.ResponseData` on success and nil if something went wrong
    @MainActor
    public func useCode(code: String) async throws -> IDoHeartUseCode.ResponseData? {
        guard let apiKeyString = apiKey else {
            logger.error("❌ Error: IDoHeart API key not set")
            throw APIError.noAPIKey
        }
        let requestBody = IDoHeartUseCode.RequestBody(code: code)
        do {
            let responseData = try await IDoHeartUseCode.postRequest(
                to: "https://idoheart.com/api/useReferral",
                with: requestBody,
                apiKey: apiKeyString
            )
            logger.debug("Success: \(responseData.success), usedCount: \(responseData.usedCount)")
            return responseData
        } catch APIError.invalidURL {
            logger.error("❌ Error: useCode: Invalid URL")
            throw APIError.invalidURL
        } catch APIError.requestFailed(let statusCode) {
            logger.error("❌ Error: useCode: Request failed with status code \(statusCode)")
            throw APIError.requestFailed(statusCode: statusCode)
        } catch APIError.decodingFailed {
            logger.error("❌ Error: useCode: Failed to decode response")
            throw APIError.decodingFailed
        } catch {
            logger.error("❌ Unknown Error: useCode: \(error)")
            throw error
        }
    }
    
    /// Async Task to check a referral code via API
    /// returns a Referral on success and nil if something went wrong
    /// Use to check usedCount to see whether it was redemed or not.
    /// usedCount == 0 means not redeemed
    /// usedCount > 0 means it was redeemed (maybe even multiple times)
    @MainActor
    public func checkCode(code: String) async throws -> Referral? {
        guard let apiKeyString = apiKey else {
            logger.error("❌ Error: IDoHeart API key not set")
            throw APIError.noAPIKey
        }
        let requestBody = IDoHeartCheckCode.RequestBody(code: code)
        do {
            let responseData = try await IDoHeartCheckCode.postRequest(
                to: "https://idoheart.com/api/checkReferral",
                with: requestBody,
                apiKey: apiKeyString
            )
            logger.debug("document RefId: \(responseData.referralRefId)")
            return responseData
        } catch APIError.invalidURL {
            logger.error("❌ Error: checkCode: Invalid URL")
            throw APIError.invalidURL
        } catch APIError.requestFailed(let statusCode) {
            logger.error("❌ Error: checkCode: Request failed with status code \(statusCode)")
            throw APIError.requestFailed(statusCode: statusCode)
        } catch APIError.decodingFailed {
            logger.error("❌ Error: checkCode: Failed to decode response")
            throw APIError.decodingFailed
        } catch {
            logger.error("❌ Unknown Error: checkCode: \(error)")
            throw error
        }
    }
}

extension IDoHeart {
    /// Define API Errors
    enum APIError: Error {
        case noAPIKey
        case invalidURL
        case requestFailed(statusCode: Int)
        case decodingFailed
    }
}

/// Helper to call the IDoHeart API to generate a referral code
fileprivate struct IDoHeartGenerateCode {
    
    // Async Function for POST Request
    public static func postRequest(to urlString: String, apiKey: String) async throws -> Referral {
        guard let url = URL(string: urlString) else {
            throw IDoHeart.APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue(apiKey, forHTTPHeaderField: "X-API-Key")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw IDoHeart.APIError.requestFailed(statusCode: (response as? HTTPURLResponse)?.statusCode ?? -1)
        }

        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .formatted(dateFormatter)
        
        do {
            return try decoder.decode(Referral.self, from: data)
        } catch {
            throw IDoHeart.APIError.decodingFailed
        }
    }
}


/// Helper to call the IDoHeart API to use/redeem a referral code
public struct IDoHeartUseCode {

    // Define Request & Response Models
    public struct RequestBody: Codable {
        let code: String
    }

    public struct ResponseData: Codable, Sendable {
        public let usedCount: Int
        public let success: Bool
    }

    // Async Function for POST Request
    public static func postRequest(to urlString: String, with body: RequestBody, apiKey: String) async throws -> ResponseData {
        guard let url = URL(string: urlString) else {
            throw IDoHeart.APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue(apiKey, forHTTPHeaderField: "X-API-Key")

        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw IDoHeart.APIError.requestFailed(statusCode: (response as? HTTPURLResponse)?.statusCode ?? -1)
        }

        do {
            return try JSONDecoder().decode(ResponseData.self, from: data)
        } catch {
            throw IDoHeart.APIError.decodingFailed
        }
    }
}

/// Helper to call the IDoHeart API to check a referral code
fileprivate struct IDoHeartCheckCode {

    // Define Request & Response Models
    struct RequestBody: Codable {
        let code: String
    }

    // Async Function for POST Request
    public static func postRequest(to urlString: String, with body: RequestBody, apiKey: String) async throws -> Referral {
        guard let url = URL(string: urlString) else {
            throw IDoHeart.APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue(apiKey, forHTTPHeaderField: "X-API-Key")

        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw IDoHeart.APIError.requestFailed(statusCode: (response as? HTTPURLResponse)?.statusCode ?? -1)
        }

        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .formatted(dateFormatter)

        do {
            return try decoder.decode(Referral.self, from: data)
        } catch {
            throw IDoHeart.APIError.decodingFailed
        }
    }
}
