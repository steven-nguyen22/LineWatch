//
//  AppRouter.swift
//  LineWatch
//
//  Created by Steven Nguyen on 3/9/26.
//

import SwiftUI

enum AppRoute: Hashable {
    case sportEvents(SportCategory)
    /// - `prefillSearch`: optional string to pre-populate the golf player search bar
    /// - `initialPlayerPropType`: optional prop tab to preselect when opening the Player Props market
    case eventDetail(ResponseBody, MarketType, String?, PlayerPropType?)
    case bestEV
    case paywall
}
