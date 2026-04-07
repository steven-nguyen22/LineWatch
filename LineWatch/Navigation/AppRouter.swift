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
    case eventDetail(ResponseBody, MarketType, String?)
    case bestEV
}
