//
//  AdManager.swift
//  InfiniteTranscription
//
//  Created by 永井涼 on 2025/06/15.
//

import Foundation

import GoogleMobileAds
import SwiftUI
import UIKit

final class AdManager: NSObject, FullScreenContentDelegate, ObservableObject {
    static let shared = AdManager()

    private var interstitial: InterstitialAd?
    
    var interstitialID: String {
    #if DEBUG
    return "ca-app-pub-3940256099942544/4411468910"// テスト広告ID
    #else
    return "ca-app-pub-1909140510546146/3037133355"
    #endif
    }

    // ———— インタースティシャル ————

    /// インタースティシャル広告をロード
    func loadInterstitial() {
        InterstitialAd.load(
            with: interstitialID,
            request: Request()
        ) { [weak self] ad, error in
            if let error = error {
                print("Interstitial failed to load: \(error.localizedDescription)")
                return
            }
            self?.interstitial = ad
            self?.interstitial?.fullScreenContentDelegate = self
        }
    }

    /// インタースティシャル広告を表示
    func showInterstitial(from root: UIViewController) {
        guard let ad = interstitial else {
            print("Interstitial not ready")
            return
        }
        ad.present(from: root)
        interstitial = nil
    }

    // ———— リワード広告 ————

    // MARK: GADFullScreenContentDelegate

    /// 広告が閉じられたら再ロード
    func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        if ad === interstitial {
            loadInterstitial()
        }
    }

    /// 広告の表示に失敗したとき（任意実装）
    func ad(_ ad: FullScreenPresentingAd,
            didFailToPresentFullScreenContentWithError error: Error) {
        print("Failed to present ad: \(error.localizedDescription)")
    }
}
