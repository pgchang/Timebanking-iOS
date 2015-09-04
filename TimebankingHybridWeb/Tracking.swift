//
//  Tracking.swift
//  TimebankingHybridWeb
//
//  Created by Ivy Chung on 6/16/15.
//  Copyright (c) 2015 Patrick Chang. All rights reserved.
//

import Foundation
import CoreData

class Tracking: NSManagedObject {

    @NSManaged var activity: String
    @NSManaged var confidence: String
    @NSManaged var latitude: String
    @NSManaged var longitude: String
    @NSManaged var timestamp: String
    @NSManaged var timezone: String
    @NSManaged var speed: String
    @NSManaged var speedAcc: String
    @NSManaged var locAcc: String
    @NSManaged var batteryLevel: String

}
