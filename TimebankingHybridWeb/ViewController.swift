//
//  ViewController.swift
//  TimebankingHybridWeb
//
//  Created by Ivy Chung on 6/16/15.
//  Copyright (c) 2015 Patrick Chang. All rights reserved.
//

import UIKit

class ViewController: UIViewController {
    
    
    @IBOutlet weak var trackingToggle: UISwitch!
    @IBOutlet weak var trackingText: UILabel!
    //Christian says the button works???
    @IBAction func switchToggled(sender: UISwitch) {
        if sender.on {
            trackingText.text = "Tracking enabled"
            AppDelegate().shouldAllow = true
        } else {
            trackingText.text = "Tracking disabled"
            AppDelegate().shouldAllow = false
        }
    }


    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
        trackingText.text = "Tracking enabled"
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }


}

