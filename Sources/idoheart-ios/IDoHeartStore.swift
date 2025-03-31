//
//  IdoHeartStore.swift
//  idoheartapp
//
//  Created by IDoHeart on 22/3/2025.
//  Copyright © 2025 3 Cups Pty Ltd. All rights reserved.
//

import SwiftUI

/// Overall store for all the referrals sent by user and wheter user has redeemed a referral code.
/// For privacy reasones the backend has no information about the user or client app.
/// So, there is no way to ask the backend for all the referrals created by this app/user without providing the referral code.
/// Instead, we  store the generated referrals locally in user defaults and use them to check with the backend.
/// Use this store to also tell the user the status of their shared invites.
/// Calling `checkReferrals()` synchonizes the local referrals with the backend.
/// `usedReferralsCount` can be used to update your UI so user can see the status of their invites.
/// You can use referrals to be used multiple times e.g if you want the user to share on social media.
/// If you want ther user to send invites using a single-use referral then you can use this store to track which
/// code was used but you need to create your own logic to create a new referral when user wants to send an invite.
/// This sample creates only one referral that can be used by many invited users.
/// We recommend to use multi-use referrals for simplicity and the benefit of sharing it on social media.
/// Redeeming a code:
/// Any user who redeems a referral code can do so only once.
/// Use `saveHasRedeemedCode(_ code: state:)` to mark that the user has redeemed a code and
/// check next time they want to redeem a code that they haven't already via `hasRedeemedBefore`

@Observable public class IDoHeartStore {
    public static let shared = IDoHeartStore()
    
    enum Key: String {
        case sentReferrals = "sentReferrals"
        case receivedCode = "receivedCode"
    }

    /// all created referrals.  (the demo only uses one referral though that can be used by multiple users)
    /// This will be synchronized with backened via `checkSentReferrals()`
    public var sentReferrals: [Referral] = [] {
        didSet {
            usedReferrals = sentReferrals.filter({$0.usedCount > 0})
        }
    }
    /// referral codes that have been used at least once
    private var usedReferrals: [Referral] = []
    // UI can subscribe to this to show as credits
    public var usedReferralsCount: Int { usedReferrals.reduce(into: 0) { $0 += $1.usedCount } }
    /// the code shared with the user. User has opened app via link using this code
    /// To check if user has received a code you can check if receicedCode != nil and then check the status
    /// if status is .installed the code was received and installed in the app but not used yet
    /// if status is .redeemed then code was redeemed
    public var receivedCode: ReceivedCode? = nil
    
    init() {
        // flag if use has redeemed a code before (can only redeem once)
        #if DEBUG
        // reset in debug mode
//        UserDefaults.standard.set("", forKey: Key.hasRedeemedCode.rawValue)
        #endif
        // user may have used a code to install app. Read from local store
        if let jsonData = UserDefaults.standard.data(forKey: Key.receivedCode.rawValue),
           let received = try? JSONDecoder().decode(ReceivedCode.self, from: jsonData) {
            self.receivedCode = received
        }
    
        // bit of debug info
        if let receivedCode, receivedCode.state == .redeemed {
            debugPrint("Redeemed code \(self.receivedCode!) used before")
        } else {
            debugPrint("No code redeemed before")
        }
        
        // Locally stored codes that were generated via API
        // This demo uses only one invite referral code though.
        var localCodes: [Referral] = []
        if let jsonData = UserDefaults.standard.data(forKey: Key.sentReferrals.rawValue),
           let decodedCodes = try? JSONDecoder().decode([Referral].self, from: jsonData) {
            localCodes = decodedCodes
        }
        self.sentReferrals = localCodes
        // bit of debug info
        debugPrint("Referral codes in UserDefaults:")
        debugPrint(sentReferrals.map({"\($0.code), \($0.usedCount)"}))
    }
    
    /// call this when the user has generated a **New** referral.
    /// Will add it to the locally stored referrals.
    public func addReferral(_ referral: Referral) {
        sentReferrals.append(referral)
        saveSentReferrals()
    }
    
    private func saveSentReferrals() {
        if let jsonData = try? JSONEncoder().encode(sentReferrals) {
            UserDefaults.standard.set(jsonData, forKey: Key.sentReferrals.rawValue)
        }
        debugPrint("Saved referral codes to UserDefaults:")
        debugPrint(sentReferrals.map({"\($0.code), \($0.usedCount)"}))
    }
    
    /// retrieve locally stored referral
    public func sentReferral(forCode code: String) -> Referral? {
        sentReferrals.first(where: {$0.code == code})
    }
    
    /// checks all locally stored referrals against the API asynchonously.
    /// Updates observed properties to allow UI to react to changes.
    @MainActor
    public func checkSentReferrals() async {
        var remoteReferrals: [Referral] = []
        for referral in sentReferrals {
            debugPrint("Checking local referral:")
            debugPrint("\(referral)")
            if let remoteReferral = await IDoHeart.shared.checkCode(code: referral.code) {
                remoteReferrals.append(remoteReferral)
                debugPrint("Remote referral:")
                debugPrint("\(remoteReferral)")
            }
        }
        debugPrint("Remote referrals:")
        debugPrint(remoteReferrals.map({"\($0.code), \($0.usedCount)"}))
        sentReferrals = remoteReferrals // update from server
        saveSentReferrals()
    }
}

// MARK: - Redeeming a received code
extension IDoHeartStore {
    
    /// When user opened the app via a referral link then we handle that as a ReceivedCode
    /// A received code can eihter be .installed or .redeemed.
    public struct ReceivedCode: Codable, Equatable {
        var code: String
        var timestamp: Date // last change (e.g. when redeemed if state == .redeemed)
        var state: ReceivedCodeState // if false then user has installed but not redeemed yet
    }
    public enum ReceivedCodeState: String, Codable {
        case installed // user has opened app via a referral link but not redeemed yet
        case redeemed // user has redeemded the received referral code
    }
    
    /// A user can only redeem one code and only one.
    /// Call this twice in the flow.
    /// 1. Call  with state .installed when user has installed a code but not yet redeemed
    /// 2. Call with state .redeemed when useReferral() returns success to keep record
    public func saveReceivedCode(_ code: String, state: ReceivedCodeState) {
        let redeemedCode = ReceivedCode(
            code: code,
            timestamp: .now,
            state: state
        )
        
        #if !DEBUG
        // check if it's user's own referral code
        guard sentReferral(forCode: code) == nil else {
            debugPrint("Cannot use own referral code -> don't save")
            return
            // Note: does not prevent user from creating a code and then deleting the app and installing the app again then applying the code. Well, if someone goes through that trouble they can have it.
        }
        #else
        #warning("User can use own referral code in debug mode.")
        #endif
            
        if let jsonData = try? JSONEncoder().encode(redeemedCode) {
            UserDefaults.standard.set(jsonData, forKey: Key.receivedCode.rawValue)
        }
        debugPrint("Saved redeemed code to UserDefaults:")
        debugPrint("\(redeemedCode.code), \(redeemedCode.state.rawValue)")
        self.receivedCode = redeemedCode
    }
    
    
#if DEBUG
    public func resetHasRedeemedCode() {
        self.receivedCode = nil
        UserDefaults.standard.removeObject(forKey: Key.receivedCode.rawValue)
        debugPrint("Reset hasRedeemedCode to nil")
    }
#endif
}
