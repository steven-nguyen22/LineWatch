//
//  AppRouter.swift
//  LineWatch
//
//  Created by Steven Nguyen on 3/9/26.
//

import SwiftUI

enum AppRoute: Hashable {
    case sportEvents(SportCategory)
    case eventDetail(ResponseBody)
}
