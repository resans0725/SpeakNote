//
//  BannerAdView.swift
//  InfiniteTranscription
//
//  Created by 永井涼 on 2025/06/15.
//

import SwiftUI
import GoogleMobileAds

struct BannerAdView: UIViewRepresentable {
    var bannerID: String 
    
    func makeUIView(context: Context) -> BannerView {
        let banner = BannerView(adSize: AdSizeBanner)
           banner.adUnitID = bannerID
           banner.rootViewController = UIApplication.shared
               .connectedScenes
               .compactMap { ($0 as? UIWindowScene)?.keyWindow?.rootViewController }
               .first
        banner.load(Request())
           return banner
       }

    func updateUIView(_ uiView: BannerView, context: Context) {}
}
