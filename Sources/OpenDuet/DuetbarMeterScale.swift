// Adapted from mulhoon/duetbar, commit 463c35f0881dfb5e40270867a1e946db6ad463bd.
// Copyright (c) 2026 Nic Mulvaney. MIT license in ThirdParty/Duetbar-LICENSE.txt.
import SwiftUI

enum DuetbarMeterScale {
    static let strongGreen = Color(red: 0.04, green: 0.76, blue: 0.24)
    static let paleGreen = Color(red: 0.62, green: 0.88, blue: 0.66)
    static let over = Color(red: 1.0, green: 0.16, blue: 0.12)

    static let anchors: [(db: Double, at: Double)] = [
        (-60, 0.00), (-40, 0.154), (-24, 0.327), (-12, 0.577), (-6, 0.808), (0, 1.00),
    ]

    static let stops: [Gradient.Stop] = [
        .init(color: strongGreen, location: 0.0),
        .init(color: strongGreen, location: 0.577),
        .init(color: paleGreen, location: 0.577),
        .init(color: paleGreen, location: 0.955),
        .init(color: over, location: 0.955),
        .init(color: over, location: 1.0),
    ]

    static func fraction(_ decibels: Double) -> Double {
        guard decibels.isFinite else { return 0 }
        if decibels <= anchors[0].db { return 0 }
        if decibels >= 0 { return 1 }
        for index in 1..<anchors.count {
            let low = anchors[index - 1], high = anchors[index]
            if decibels <= high.db {
                let t = (decibels - low.db) / (high.db - low.db)
                return low.at + t * (high.at - low.at)
            }
        }
        return 1
    }
}
