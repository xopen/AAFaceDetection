//
//  ViewController.swift
//  FaceDetection
//
//  Created by Julian Abentheuer on 21.12.14.
//  Copyright (c) 2014 Aaron Abentheuer. All rights reserved.
//

import UIKit
import NotificationCenter

class ViewController: UIViewController {
    
    private var visage : Visage?
    private let notificationCenter : NotificationCenter = NotificationCenter.default
    
    let emojiLabel : UILabel = UILabel(frame: UIScreen.main.bounds)
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        //Setup "Visage" with a camera-position (iSight-Camera (Back), FaceTime-Camera (Front)) and an optimization mode for either better feature-recognition performance (HighPerformance) or better battery-life (BatteryLife)
        visage = Visage(cameraPosition: Visage.CameraDevice.FaceTimeCamera, optimizeFor: Visage.DetectorAccuracy.HigherPerformance)
        
        //If you enable "onlyFireNotificationOnStatusChange" you won't get a continuous "stream" of notifications, but only one notification once the status changes.
        visage!.onlyFireNotificatonOnStatusChange = false
        
        
        //You need to call "beginFaceDetection" to start the detection, but also if you want to use the cameraView.
        visage!.beginFaceDetection()
        
        //This is a very simple cameraView you can use to preview the image that is seen by the camera.
        let cameraView = visage!.visageCameraView
        self.view.addSubview(cameraView)
        
        let visualEffectView = UIVisualEffectView(effect: UIBlurEffect(style: .light))
        visualEffectView.frame = self.view.bounds
        self.view.addSubview(visualEffectView)

        emojiLabel.text = "😐"
        emojiLabel.font = UIFont.systemFont(ofSize: 50)
        emojiLabel.textAlignment = .center
        self.view.addSubview(emojiLabel)
        
        //Subscribing to the "visageFaceDetectedNotification" (for a list of all available notifications check out the "ReadMe" or switch to "Visage.swift") and reacting to it with a completionHandler. You can also use the other .addObserver-Methods to react to notifications.

        let center = NotificationCenter.default
        let mainQueue = OperationQueue.main





       center.addObserver(forName: Notification.Name(rawValue: "visageFaceDetectedNotification"), object: nil, queue: mainQueue) { (notification) in
            
            UIView.animate(withDuration: 0.5, animations: {
                self.emojiLabel.alpha = 1

            })
            
            if ((self.visage!.hasSmile == true && self.visage!.isWinking == true)) {
                self.emojiLabel.text = "😜"
            } else if ((self.visage!.isWinking == true && self.visage!.hasSmile == false)) {
                self.emojiLabel.text = "😉"
            } else if ((self.visage!.hasSmile == true && self.visage!.isWinking == false)) {
                self.emojiLabel.text = "😃"
            } else {
                self.emojiLabel.text = "😐"
            }
        }
//
//        //The same thing for the opposite, when no face is detected things are reset.
      center.addObserver(forName: Notification.Name(rawValue: "visageFaceDetectedNotification"), object: nil, queue: mainQueue) { (notification) in
            UIView.animate(withDuration: 0.5, animations: {
                self.emojiLabel.alpha = 0.25
            })
        }
    }
    
    override var prefersStatusBarHidden: Bool {
        return true
    }
}
