//
//  AppDelegate.swift
//  InfiniteTranscription
//
//  Created by 永井涼 on 2025/06/15.
//

import UIKit
import GoogleMobileAds
import FirebaseCore
import Firebase

class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        FirebaseApp.configure()
        MobileAds.shared.start(completionHandler: nil)
        
        // 起動時にイベントをログ
        Analytics.logEvent("app_launch", parameters: [
            "timestamp": Date().timeIntervalSince1970
        ])
        
        return true
    }
}
