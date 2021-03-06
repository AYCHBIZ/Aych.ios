//
//  StellarAirdropRouterTests.swift
//  BlockchainTests
//
//  Created by Chris Arriola on 10/30/18.
//  Copyright © 2018 Blockchain Luxembourg S.A. All rights reserved.
//

import RxSwift
import StellarKit
import XCTest

@testable import Blockchain

class StellarAirdropRouterTests: XCTestCase {

    private var mockAppSettings: MockBlockchainSettingsApp!
    private var mockStellarBridge: MockStellarBridge!
    private var mockDataRepo: MockBlockchainDataRepository!
    private var mockAirdropRegistration: AirdropRegistrationMock!
    private var mockKYCSettings: KYCSettingsMock!
    private var mockNabuAuthenticationService: NabuAuthenticationServiceMock!
    private var stellarWalletAccountRepository: StellarWalletAccountRepository!
    
    private var router: StellarAirdropRouter!

    override func setUp() {
        super.setUp()
        
        mockAppSettings = MockBlockchainSettingsApp()
        mockDataRepo = MockBlockchainDataRepository()
        mockStellarBridge = MockStellarBridge()
        mockAirdropRegistration = AirdropRegistrationMock()
        mockKYCSettings = KYCSettingsMock()
        mockNabuAuthenticationService = NabuAuthenticationServiceMock()
        stellarWalletAccountRepository = StellarWalletAccountRepository(with: mockStellarBridge)
        
        router = StellarAirdropRouter(
            kycSettings: mockKYCSettings,
            airdropRegistrationService: mockAirdropRegistration,
            nabuAuthenticationService: mockNabuAuthenticationService,
            appSettings: mockAppSettings,
            repository: mockDataRepo,
            stellarWalletAccountRepository: stellarWalletAccountRepository
        )
    }

    func testRoutesIfTappedOnDeepLink() {
        mockAppSettings.mockDidTapOnAirdropDeepLink = true
        mockStellarBridge.accounts = [
            StellarWalletAccount(index: 0, publicKey: "public key", label: "label", archived: false)
        ]
        mockDataRepo.mockNabuUser = NabuUser(
            personalDetails: nil,
            address: nil,
            email: Email(address: "test", verified: false),
            mobile: nil,
            status: KYCAccountStatus.none,
            state: NabuUser.UserState.none,
            tags: Tags(),
            tiers: nil,
            needsDocumentResubmission: nil
        )
        let exp = expectation(
            description: "Expects that registration is attempted through router when user has deeplinked."
        )
        mockAirdropRegistration.didCallSubmitRegistrationRequest = { _ in
            exp.fulfill()
        }
        router.routeIfNeeded()
        waitForExpectations(timeout: 5)
    }

    func testDoesNotRouteIfDidntTapOnDeepLink() {
        mockAppSettings.mockDidTapOnAirdropDeepLink = false
        let exp = expectation(
            description: "Expects that registration is NOT attempted through router when user has NOT deeplinked."
        )
        exp.isInverted = true
        router.routeIfNeeded()
        waitForExpectations(timeout: 0.1)
    }
}
