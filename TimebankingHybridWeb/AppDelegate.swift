//
//  AppDelegate.swift
//  test1
//
//  Created by Ivy Chung on 6/16/15.
//  Copyright (c) 2015 Patrick Chang. All rights reserved.
//

import Foundation
import UIKit
import CoreData
import UIKit

import CoreLocation
import CoreMotion
import SystemConfiguration


//used for checkting connectivity to the internet
public class Reachability {
    
    class func isConnectedToNetwork() -> Bool {
        
        var zeroAddress = sockaddr_in(sin_len: 0, sin_family: 0, sin_port: 0, sin_addr: in_addr(s_addr: 0), sin_zero: (0, 0, 0, 0, 0, 0, 0, 0))
        zeroAddress.sin_len = UInt8(sizeofValue(zeroAddress))
        zeroAddress.sin_family = sa_family_t(AF_INET)
        
        let defaultRouteReachability = withUnsafePointer(&zeroAddress) {
            SCNetworkReachabilityCreateWithAddress(nil, UnsafePointer($0)).takeRetainedValue()
        }
        
        var flags: SCNetworkReachabilityFlags = 0
        if SCNetworkReachabilityGetFlags(defaultRouteReachability, &flags) == 0 {
            return false
        }
        
        let isReachable = (flags & UInt32(kSCNetworkFlagsReachable)) != 0
        let needsConnection = (flags & UInt32(kSCNetworkFlagsConnectionRequired)) != 0
        
        return (isReachable && !needsConnection) ? true : false
    }
    
}

extension NSURLSessionTask{ func start(){
    self.resume() }
}


@UIApplicationMain

class AppDelegate: UIResponder, UIApplicationDelegate, CLLocationManagerDelegate {
    
    var viewController = ViewController()
    //location & activity tracking variables
    var window: UIWindow?
    var locationManager: CLLocationManager!
    var seenError : Bool = false
    var locationStatus : NSString = "Not Started"
    let activityManager: CMMotionActivityManager = CMMotionActivityManager()
    let dataProcessingQueue = NSOperationQueue()
    //server upload variables
    var updatingLocation :Bool = false
    var locationLongitude = "initLong"
    var locationLatitude = "initLat"
    var activityType = "initAct"
    var activityConfidence = "1"
    var speed = "initSpeed"
    var locAcc = "initLocAcc"
    var offlineUpload = [[String]]()
    var uploadContents = ["lat", "long", "UNKNOWN", "conf", "timestamp", "timezone", "speed", "batteryLeft", "connection", "timezone","locAcc", "batteryLevel"]
    var oldTime = NSDate().timeIntervalSince1970
    var uploadString = ""
    var shouldStopTracking = false
    var shouldAllow = true
    
    var firstTime = true
    var oldLocation : CLLocation!
    //ensures that larger batch uploads do not time out
    let batchLimit = 20
    var batchArray :NSMutableArray = []
    var batchCounter = 0
    var batteryChargeLast = 0
    var lastUploadFromDB = Int(NSDate().timeIntervalSince1970)
    var timeAsString : String = ""
    
    
    let deviceIDBase64 = UIDevice.currentDevice().identifierForVendor.UUIDString.dataUsingEncoding(NSUTF8StringEncoding)!.base64EncodedStringWithOptions(NSDataBase64EncodingOptions(rawValue: 0))
    
    func application(application: UIApplication, didFinishLaunchingWithOptions launchOptions: [NSObject: AnyObject]?) -> Bool {
        initLocationManager();
        return true
    }


    //Changing the settings of our location manager
    func initLocationManager() {
        println("starting location manager")
        UIDevice.currentDevice().batteryMonitoringEnabled = true
        locationManager = CLLocationManager()
        locationManager.delegate = self
        //locationManager.locationServicesEnabled
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        locationManager.pausesLocationUpdatesAutomatically = false
        locationManager.distanceFilter = 0
        //println(self.deviceIDBase64)
        locationManager.requestAlwaysAuthorization()
    }
    
    // Starting our location manager and checks if it fails or works properly
    func locationManager(manager: CLLocationManager!, didFailWithError error: NSError!) {
        locationManager.stopUpdatingLocation()
        updatingLocation = false
        if ((error) != nil) {
            if (seenError == false) {
                seenError = true
                print(error)
            }
        }
    }

    //This method gets called whenever a new event is detected by the iOS
    //These events are triggered whenever the device detects that it has moved a certain
    //distance; in this iteration it is 250m.
    //After detecting an event from the iOS, we record the data into the internal
    //database, then check the activity, and log that into the database as well.
    //Once both activity and location are logged in the database, we upload the data
    //to the webservice
    func locationManager(manager: CLLocationManager!, didUpdateLocations locations: [AnyObject]!) {
        //println("new instance found")
        //println("\(shouldAllow)")
        if shouldAllow {
            //setting location information in database
            let tracking = NSEntityDescription.insertNewObjectForEntityForName("Tracking", inManagedObjectContext: self.managedObjectContext!) as! Tracking
            var locationArray = locations as NSArray
            var locationObj = locationArray.lastObject as! CLLocation
            var coord = locationObj.coordinate
            var batchString = ""
            
            
            //new stuff as of 9/3/2015
            if self.firstTime {
                self.oldLocation = locationObj
                self.firstTime = false
                return
            }
            self.firstTime = true
            let distance = oldLocation.distanceFromLocation(locationObj)
            let timeDiff = locationObj.timestamp.timeIntervalSinceDate(oldLocation.timestamp)
            let speedCalc = distance/timeDiff
            
            
            
            
            
            
            self.locationLongitude = "\(coord.longitude)"
            self.locationLatitude = "\(coord.latitude)"
            self.locAcc = "\(locationObj.horizontalAccuracy)"
            self.speed = "\(speedCalc)"
            tracking.longitude = self.locationLongitude
            tracking.latitude = self.locationLatitude
            tracking.speed = "\(locationObj.speed)"
            tracking.locAcc = "\(locationObj.horizontalAccuracy)"
            tracking.speedAcc = "-1"
            uploadContents[0] = self.locationLatitude
            uploadContents[1] = self.locationLongitude
            uploadContents[6] = "\(speedCalc)"
            uploadContents[10] = self.locAcc
            self.activityManager.startActivityUpdatesToQueue(self.dataProcessingQueue) {
                data in
                dispatch_async(dispatch_get_main_queue()) {
                    //setting confidence level in DB
                    if data.confidence == CMMotionActivityConfidence.Low {
                        self.activityConfidence = "25"  //low
                    } else if data.confidence == CMMotionActivityConfidence.Medium {
                        self.activityConfidence = "50"  //medium
                    } else if data.confidence == CMMotionActivityConfidence.High {
                        self.activityConfidence = "90"  //high
                    } else {
                        self.activityConfidence = "There was a problem getting confidence"
                    }
                    if data.running {
                        //println("the current activity is running")
                        self.activityManager.stopActivityUpdates()
                        //self.locationManager.pausesLocationUpdatesAutomatically = true
                        self.activityType = "RUNNING"
                    }; if data.cycling {
                        //println("the current activity is cycling")
                        self.activityManager.stopActivityUpdates()
                        //self.locationManager.pausesLocationUpdatesAutomatically = true
                        self.activityType = "ON_BICYCLE"
                    };if data.walking {
                        //println("the current activity is walking")
                        self.activityManager.stopActivityUpdates()
                        //self.locationManager.pausesLocationUpdatesAutomatically = true
                        self.activityType = "WALKING"
                    }; if data.automotive {
                        //println("the current activity is automotive")
                        self.activityManager.stopActivityUpdates()
                        //self.locationManager.pausesLocationUpdatesAutomatically = false
                        self.activityType = "IN_VEHICLE"
                    }; if data.stationary{
                        //println("the current activity is stationary")
                        self.activityManager.stopActivityUpdates()
                        //self.locationManager.pausesLocationUpdatesAutomatically = true
                        self.activityType = "STILL"
                    }; if data.unknown {
                        //println("the current activity is unknown")
                        self.activityManager.stopActivityUpdates()
                        //self.locationManager.pausesLocationUpdatesAutomatically = true
                        self.activityType = "UNKNOWN"
                    }
                    //var googleActivity :String = self.convertToGoogleActivityType(self.activityType)
                    self.uploadContents[2] = self.activityType
                    self.uploadContents[3] = self.activityConfidence
                    tracking.activity = self.activityType
                    tracking.confidence = self.activityConfidence
                }
            }
            tracking.timestamp = "\(Int(NSDate().timeIntervalSince1970))"
            tracking.timezone = "\(NSTimeZone.localTimeZone().abbreviation!)"
            uploadContents[5] = tracking.timezone
            println(tracking.timezone)
            //creating the upload string
            let date = NSDate();
            let dateFormatter = NSDateFormatter()
            //To prevent displaying either date or time, set the desired style to NoStyle.
            dateFormatter.timeStyle = NSDateFormatterStyle.LongStyle //Set time style
            dateFormatter.dateStyle = NSDateFormatterStyle.LongStyle //Set date style
            dateFormatter.timeZone = NSTimeZone()
            let localDate = dateFormatter.stringFromDate(date)
            uploadContents[4] = "\(Int(NSDate().timeIntervalSince1970))"
            uploadContents[9] = baseEncodeTimeZone()
            var batteryLeft = ""
            batteryLeft = "\(Int(UIDevice.currentDevice().batteryLevel*100))"
            tracking.batteryLevel = batteryLeft
            if Int(UIDevice.currentDevice().batteryLevel*100) > self.batteryChargeLast{
                var instances = instancesSinceLastUpload(String(self.lastUploadFromDB))
                println("Since the last upload, we have had \(instances) new instances")
                self.lastUploadFromDB = Int(NSDate().timeIntervalSince1970)
            }
            self.batteryChargeLast = Int(UIDevice.currentDevice().batteryLevel*100)
            uploadContents[7] = batteryLeft
            //println(offlineUpload.count)
            //Data upload
            if Reachability.isConnectedToNetwork() {
                if self.uploadString != "" || batchArray.count > 0 {
                    sendBatchToWebService(self.uploadString, batchFromDB: false)
                    while batchArray.count > 0 {
                        self.uploadString = batchArray[0] as! String
                        sendBatchToWebService(self.uploadString, batchFromDB: false)
                        batchArray.removeObjectAtIndex(0)
                    }
                }
                println(uploadContents)
                sendToWebservice(uploadContents[2], timestampString: uploadContents[4], latitudeString: uploadContents[1], longitudeString: uploadContents[0], speedString: uploadContents[6], timezoneString: uploadContents[9], confidenceString: uploadContents[3], batteryString: uploadContents[7], locAccString: uploadContents[10])
                
            } else {
                self.batchCounter += 1
                uploadContents[8] = "Not connected"
                batchString = batchStringBuilder(uploadContents[4], timezone: uploadContents[9], latitude: uploadContents[1], longitude: uploadContents[0], activity: uploadContents[2], confidence: uploadContents[3], speed: uploadContents[6], batteryLevel :uploadContents[7], locAcc: uploadContents[10], speedAcc: "-1")
                self.uploadString = self.uploadString + batchString
                println(self.uploadString)
                //checks to see if the number of instances in this batch is at the limit as set above
                //if yes, add it to the array and start a new batch String
                if self.batchCounter == self.batchLimit {
                    self.batchArray.addObject(self.uploadString)
                    self.uploadString = ""
                }
            }
            //save the data written to the database
            self.saveContext()
        }

    }
        
        
    func instancesSinceLastUpload(lastUploadTimestamp: String) ->Int {
        // print out number of instances stored in database
        var request = NSFetchRequest(entityName: "Tracking")
        //let appDelegate:AppDelegate = (UIApplication.sharedApplication().delegate as! AppDelegate)
        //let context:NSManagedObjectContext = appDelegate.managedObjectContext!
        let predicate = NSPredicate(format: "timestamp > %@", lastUploadTimestamp )
        request.predicate = predicate
        request.returnsObjectsAsFaults = false
        var batchString = ""
        var backupCounter = 0
        if let result = managedObjectContext!.executeFetchRequest(request, error:nil){
            println("The number of entries in this fetch is \(result.count)")
            println(result[result.count-1])
            for log in result {
                var entryActivity: String? = log.valueForKey("activity") as? String
                var entryConfidence: String? = log.valueForKey("confidence") as? String
                var entryLatitude: String? = log.valueForKey("latitude") as? String
                var entryLongitude: String? = log.valueForKey("longitude") as? String
                var entryTimestamp: String? = log.valueForKey("timestamp") as? String
                var entryTimezone: AnyObject? = log.valueForKey("timezone") as? String
                var entryLocAcc: String? = log.valueForKey("locAcc") as? String
                var entrySpeed: String? = log.valueForKey("speed") as? String
                var entrySpeedAcc: String? = log.valueForKey("speedAcc") as? String
                var entryBatteryLevel: String? = log.valueForKey("batteryLevel") as? String
                //build string here
                
                
                if entryActivity != nil && entryConfidence != nil && entryLatitude != nil && entryLongitude != nil && entryTimestamp != nil && entryTimezone != nil && entryLocAcc != nil && entrySpeed != nil && entrySpeedAcc != nil && entryBatteryLevel != nil{
                    backupCounter += 1
                    //println("\(entryActivity!), \(entryConfidence!), \(entryLatitude!), \(entryLongitude!), \(entryTimestamp!), \(entryTimezone!), \(entryLocAcc!), \(entrySpeed!), \(entrySpeedAcc!), \(entryBatteryLevel!)")
                    
                    let timezoneString1 :AnyObject = entryTimezone!
                    if timezoneString1.lowercaseString.rangeOfString("optional") != nil {
                        println("exists")
                        //println("\(timezoneString1[))
                    }
                    println("the time zone is " + (timezoneString1 as! String))
                    
                    batchString = batchString + batchStringBuilder(entryTimestamp!, timezone: entryTimezone! as! String, latitude: entryLatitude!, longitude: entryLongitude!, activity: entryActivity!, confidence: entryConfidence!, speed: entrySpeed!, batteryLevel: entryBatteryLevel!, locAcc: entryLocAcc!, speedAcc: entrySpeedAcc!)
                    println(batchString)
                    if backupCounter == 20 {
                        sendBatchToWebService(batchString, batchFromDB: true)
                        batchString = ""
                    }
                }
            }
            println("sending to web service with count of \(backupCounter)")
            if batchString != ""{
                sendBatchToWebService(batchString, batchFromDB: true)
            }
            return result.count
        }
        println("instancesSinceLastUpload failed")
        return 0
    }

    
    
    // authorization status
    func locationManager(manager: CLLocationManager!,
        didChangeAuthorizationStatus status: CLAuthorizationStatus) {
            var shouldIAllow = false
            switch status {
            case CLAuthorizationStatus.Restricted:
                locationStatus = "Restricted Access to location"
            case CLAuthorizationStatus.Denied:
                locationStatus = "User denied access to location"
            case CLAuthorizationStatus.NotDetermined:
                locationStatus = "Status not determined"
                
            default:
                locationStatus = "Allowed to location Access"
                shouldIAllow = true
            }
            NSNotificationCenter.defaultCenter().postNotificationName("LabelHasbeenUpdated", object: nil)
            if (shouldIAllow == true) {
                NSLog("Location to Allowed")
                // Start location services
                locationManager.startUpdatingLocation()
                updatingLocation = true
            } else {
                NSLog("Denied access: \(locationStatus)")
            }
    }
    
    //sending data in batches to the webservice
    func sendBatchToWebService(urlEnding: String, batchFromDB : Bool) {
        //println("sending batch to web service...")
        var response: NSURLResponse?
        //formatting
        var endURL = urlEnding
        let substringIndex = count(endURL) - 1
        let newEnding = endURL.substringToIndex(advance(endURL.startIndex,substringIndex))
        //upload to web service
        
        let myUrl = NSURL(string: "http://ridesharing.cmu-tbank.com/reportActivity.php?userID=1&deviceID=\(self.deviceIDBase64)&logs=\(newEnding)")
        let request = NSMutableURLRequest(URL:myUrl!)
        request.HTTPMethod = "POST"
        var data = NSURLConnection.sendSynchronousRequest(request, returningResponse: &response, error: nil) as NSData?
        if let httpResponse = response as? NSHTTPURLResponse {
            //OK
            if httpResponse.statusCode == 200 {
                //println("ok")
                if let json: NSDictionary = NSJSONSerialization.JSONObjectWithData(data!, options: NSJSONReadingOptions.MutableContainers, error: nil) as? NSDictionary {
                    // println("stage 1 passed")
                    if let success = json["success"] as? Bool {
                        if success {
                            println("Batch Upload: Activities reported successfully, clearning stored data")
                            if !batchFromDB{
                                self.uploadString = ""
                            }
                        }
                        if let message = json["message"] as? NSString {
                            println(message)
                        }
                    }
                }
            } else if httpResponse.statusCode == 400 {
                println("Bad Request")
            } else {
                println("Error is \(httpResponse.statusCode)")
            }
        }
    }
    
    //send on the fly to the t-bank web service
    func sendToWebservice(activityString: String,timestampString: String, latitudeString : String, longitudeString :String, speedString :String, timezoneString: String, confidenceString: String, batteryString: String, locAccString :String) {
        var response: NSURLResponse?
        let myUrl = NSURL(string: "http://ridesharing.cmu-tbank.com/reportActivity.php?userID=1&deviceID=\(self.deviceIDBase64)=&activity=\(activityString)&activityConfidence=\(activityConfidence)&currentTime=\(timestampString)&timeZone=\(timezoneString)&lat=\(latitudeString)&lng=-\(longitudeString)&locationAccuracy=\(locAccString)&speed=\(speedString)&speedAccuracy=-1&batteryLevel=\(batteryString)")
        let request = NSMutableURLRequest(URL:myUrl!)
        request.HTTPMethod = "POST"
        println(myUrl!)
        //getting a response from the server
        var data = NSURLConnection.sendSynchronousRequest(request, returningResponse: &response, error: nil) as NSData?
        if let httpResponse = response as? NSHTTPURLResponse {
            if httpResponse.statusCode == 200 { //Good connection
                if let json: NSDictionary = NSJSONSerialization.JSONObjectWithData(data!, options: NSJSONReadingOptions.MutableContainers, error: nil) as? NSDictionary {
                    if let success = json["success"] as? Bool{ // check success status
                        if let message = json["message"] as? NSDictionary {
                            println("Single instance: \(message)")
                        }
                    }
                }
            } else if httpResponse.statusCode == 400 {
                println("Bad Request")
            } else {
                println("Error is \(httpResponse.statusCode)")
            }
        }
    }
    
    //used to send data in batches to local ftp server
    func sendToServerBatch() {
        var itemsToUpload = 25
        var i = 0
        let myUrl = NSURL(string: "http://epiwork.hcii.cs.cmu.edu/~afsaneh/ChristianHybrid.php")
        let request = NSMutableURLRequest(URL:myUrl!)
        request.HTTPMethod = "POST"
        var postString = "\(UIDevice.currentDevice().identifierForVendor.UUIDString)"
        if offlineUpload.count < 25 {
            itemsToUpload = offlineUpload.count
        }
        while i < (itemsToUpload - 1) {
            println(offlineUpload[0])
            postString = postString + "Device ID=\(UIDevice.currentDevice().identifierForVendor.UUIDString), batteryLeft=\(offlineUpload[0][7]), longitude=\(offlineUpload[0][1]), latitude=\(offlineUpload[0][0]), type=\(offlineUpload[0][2]), confidence=\(offlineUpload[0][3]), timestamp=\(offlineUpload[0][4]), timezone=\(offlineUpload[0][5]),connection=\(offlineUpload[0][8])\n)"
            offlineUpload.removeAtIndex(0)
            i += 1
        }
        
        println(postString)
        request.HTTPBody = postString.dataUsingEncoding(NSUTF8StringEncoding)
        let task = NSURLSession.sharedSession().dataTaskWithRequest(request) {
            data, response, error in
            if error != nil {
                println("error=\(error)")
                return
            }
            var err: NSError?
            var myJSON = NSJSONSerialization.JSONObjectWithData(data, options: .MutableLeaves, error:&err) as? NSDictionary
        }
        println("data sent to server")
        task.resume()
    }
    
    //used to send data on the fly to a local ftp server
    func sendToServer(longitudeString: String, latitudeString: String, activityString: String, confidenceString: String, timestampString: String, timeZoneString: String, batteryChargeLeft :String, connectionString: String) {
        //let myUrl = NSURL(string: "http://cmu-tbank.com/~afsaneh@cmu-tbank.com/uploadScript.php")
        let myUrl = NSURL(string: "http://epiwork.hcii.cs.cmu.edu/~afsaneh/ChristianHybrid.php");
        println(myUrl)
        let request = NSMutableURLRequest(URL:myUrl!);
        request.HTTPMethod = "POST";
        //modify strings for formatting
        let stringBuffer = ", "
        let deviceString = UIDevice.currentDevice().identifierForVendor.UUIDString + stringBuffer
        let batteryString = batteryChargeLeft + stringBuffer
        let longitudeString2 = longitudeString + stringBuffer
        let latitudeString2 = latitudeString + stringBuffer
        let activityString2 = activityString + stringBuffer
        let confidenceString2 = confidenceString + stringBuffer
        // Compose a query string
        let postString = "deviceID=\(deviceString)&batteryLeft=\(batteryString)&longitude=\(longitudeString2)&latitude=\(latitudeString2)&type=\(activityString2)&confidence=\(confidenceString2)&timestamp=\(timestampString)&timezone=\(timeZoneString)&connection=\(connectionString)";
        
        request.HTTPBody = postString.dataUsingEncoding(NSUTF8StringEncoding);
        
        let task = NSURLSession.sharedSession().dataTaskWithRequest(request) {
            data, response, error in
            if error != nil {
                println("error=\(error)")
                return
            }
            var err: NSError?
            var myJSON = NSJSONSerialization.JSONObjectWithData(data, options: .MutableLeaves, error:&err) as? NSDictionary
        }
        println("data sent to server")
        task.resume()
    }
    
    //used to generate the base64encoded timezone of data collection
    func baseEncodeTimeZone() -> String {
        //generating the timezone string
        var timeZoneString = ""
        let timeZoneInt = (("\(NSTimeZone.localTimeZone().secondsFromGMT/3600)").toInt()!)
        let timeZoneModifier = ":00"
        if timeZoneInt >= 0 {
            timeZoneString = timeZoneString + "+"
        } else if timeZoneInt < 0 {
            timeZoneString = timeZoneString + "-"
        }
        if abs(timeZoneInt) < 10 {
            timeZoneString = timeZoneString + "0"
        }
        timeZoneString = timeZoneString + "\(abs(timeZoneInt))" + timeZoneModifier
        println(timeZoneString)
        
        //encoding the string as base64
        let utf8str = timeZoneString.dataUsingEncoding(NSUTF8StringEncoding)
        if let base64Encoded = utf8str?.base64EncodedStringWithOptions(NSDataBase64EncodingOptions(rawValue: 0))
        {
            println("Encoded:  \(base64Encoded)")
            return base64Encoded
        }
        return "ERROR"
    }
    
    //used to properly format the string used for data upload
    func batchStringBuilder(timestamp :String, timezone: String, latitude :String, longitude :String, activity :String, confidence: String, speed :String, batteryLevel: String, locAcc :String, speedAcc :String) -> String{
        //timestamp@timezone@lat@lng@locAcc@googleActivity@activityConfidence@speed@speedAcc@batteryLevel
        var batchString = ""
        let batchBuffer = "@"
        let logEnder = "*"
        batchString = batchString + timestamp + batchBuffer
        batchString = batchString + timezone + batchBuffer
        batchString = batchString + latitude + batchBuffer
        batchString = batchString + longitude + batchBuffer
        batchString = batchString + locAcc + batchBuffer
        batchString = batchString + activity + batchBuffer
        batchString = batchString + confidence + batchBuffer
        batchString = batchString + speed + batchBuffer
        batchString = batchString + speedAcc + batchBuffer
        batchString = batchString + batteryLevel + logEnder
        return batchString
    }
    
  
    
    func applicationWillResignActive(application: UIApplication) {
        // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
        // Use this method to pause ongoing tasks, disable timers, and throttle down OpenGL ES frame rates. Games should use this method to pause the game.
    }
    
    func applicationDidEnterBackground(application: UIApplication) {
        // Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later.
        // If your application supports background execution, this method is called instead of applicationWillTerminate: when the user quits.
    }
    
    func applicationWillEnterForeground(application: UIApplication) {
        // Called as part of the transition from the background to the inactive state; here you can undo many of the changes made on entering the background.
    }
    
    func applicationDidBecomeActive(application: UIApplication) {
        // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
    }
    
    func applicationWillTerminate(application: UIApplication) {
        // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
        // Saves changes in the application's managed object context before the application terminates.
    }
    
    
    // MARK: - Core Data stack
    
    lazy var applicationDocumentsDirectory: NSURL = {
        // The directory the application uses to store the Core Data store file. This code uses a directory named "UbiCompLab-CMU.test1" in the application's documents Application Support directory.
        let urls = NSFileManager.defaultManager().URLsForDirectory(.DocumentDirectory, inDomains: .UserDomainMask)
        return urls[urls.count-1] as! NSURL
        }()
    
    lazy var managedObjectModel: NSManagedObjectModel = {
        // The managed object model for the application. This property is not optional. It is a fatal error for the application not to be able to find and load its model.
        let modelURL = NSBundle.mainBundle().URLForResource("TimebankingHybridWeb", withExtension: "momd")!
        return NSManagedObjectModel(contentsOfURL: modelURL)!
        }()
    
    lazy var persistentStoreCoordinator: NSPersistentStoreCoordinator? = {
        // The persistent store coordinator for the application. This implementation creates and return a coordinator, having added the store for the application to it. This property is optional since there are legitimate error conditions that could cause the creation of the store to fail.
        // Create the coordinator and store
        var coordinator: NSPersistentStoreCoordinator? = NSPersistentStoreCoordinator(managedObjectModel: self.managedObjectModel)
        let url = self.applicationDocumentsDirectory.URLByAppendingPathComponent("TimebankingHybridWeb.sqlite")
        var error: NSError? = nil
        var failureReason = "There was an error creating or loading the application's saved data."
        if coordinator!.addPersistentStoreWithType(NSSQLiteStoreType, configuration: nil, URL: url, options: nil, error: &error) == nil {
            coordinator = nil
            // Report any error we got.
            var dict = [String: AnyObject]()
            dict[NSLocalizedDescriptionKey] = "Failed to initialize the application's saved data"
            dict[NSLocalizedFailureReasonErrorKey] = failureReason
            dict[NSUnderlyingErrorKey] = error
            error = NSError(domain: "YOUR_ERROR_DOMAIN", code: 9999, userInfo: dict)
            // Replace this with code to handle the error appropriately.
            // abort() causes the application to generate a crash log and terminate. You should not use this function in a shipping application, although it may be useful during development.
            NSLog("Unresolved error \(error), \(error!.userInfo)")
            abort()
        }
        
        return coordinator
        }()
    
    lazy var managedObjectContext: NSManagedObjectContext? = {
        // Returns the managed object context for the application (which is already bound to the persistent store coordinator for the application.) This property is optional since there are legitimate error conditions that could cause the creation of the context to fail.
        let coordinator = self.persistentStoreCoordinator
        if coordinator == nil {
            return nil
        }
        var managedObjectContext = NSManagedObjectContext()
        managedObjectContext.persistentStoreCoordinator = coordinator
        return managedObjectContext
        }()
    
    // MARK: - Core Data Saving support
    
    func saveContext () {
        if let moc = self.managedObjectContext {
            var error: NSError? = nil
            if moc.hasChanges && !moc.save(&error) {
                // Replace this implementation with code to handle the error appropriately.
                // abort() causes the application to generate a crash log and terminate. You should not use this function in a shipping application, although it may be useful during development.
                NSLog("Unresolved error \(error), \(error!.userInfo)")
                abort()
            }
        }
    }
    
}

