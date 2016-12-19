//
//  Visage.swift
//  FaceDetection
//
//  Created by Julian Abentheuer on 21.12.14.
//  Copyright (c) 2014 Aaron Abentheuer. All rights reserved.
//

import UIKit
import CoreImage
import AVFoundation
import ImageIO

class Visage: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    
    enum DetectorAccuracy {
        case BatterySaving
        case HigherPerformance
    }
    
    enum CameraDevice {
        case ISightCamera
        case FaceTimeCamera
    }
    
    var onlyFireNotificatonOnStatusChange : Bool = true
    var visageCameraView : UIView = UIView()
    
    //Private properties of the detected face that can be accessed (read-only) by other classes.
    private(set) var faceDetected : Bool?
    private(set) var faceBounds : CGRect?
    private(set) var faceAngle : CGFloat?
    private(set) var faceAngleDifference : CGFloat?
    private(set) var leftEyePosition : CGPoint?
    private(set) var rightEyePosition : CGPoint?
    
    private(set) var mouthPosition : CGPoint?
    private(set) var hasSmile : Bool?
    private(set) var isBlinking : Bool?
    private(set) var isWinking : Bool?
    private(set) var leftEyeClosed : Bool?
    private(set) var rightEyeClosed : Bool?
    
    //Notifications you can subscribe to for reacting to changes in the detected properties.
    private let visageNoFaceDetectedNotification = NSNotification(name: NSNotification.Name(rawValue: "visageNoFaceDetectedNotification"), object: nil)
    private let visageFaceDetectedNotification = NSNotification(name: NSNotification.Name(rawValue: "visageFaceDetectedNotification"), object: nil)
    private let visageSmilingNotification = NSNotification(name: NSNotification.Name(rawValue: "visageHasSmileNotification"), object: nil)
    private let visageNotSmilingNotification = NSNotification(name: NSNotification.Name(rawValue: "visageHasNoSmileNotification"), object: nil)
    private let visageBlinkingNotification = NSNotification(name: NSNotification.Name(rawValue: "visageBlinkingNotification"), object: nil)
    private let visageNotBlinkingNotification = NSNotification(name: NSNotification.Name(rawValue: "visageNotBlinkingNotification"), object: nil)
    private let visageWinkingNotification = NSNotification(name: NSNotification.Name(rawValue: "visageWinkingNotification"), object: nil)
    private let visageNotWinkingNotification = NSNotification(name: NSNotification.Name(rawValue: "visageNotWinkingNotification"), object: nil)
    private let visageLeftEyeClosedNotification = NSNotification(name: NSNotification.Name(rawValue: "visageLeftEyeClosedNotification"), object: nil)
    private let visageLeftEyeOpenNotification = NSNotification(name: NSNotification.Name(rawValue: "visageLeftEyeOpenNotification"), object: nil)
    private let visageRightEyeClosedNotification = NSNotification(name: NSNotification.Name(rawValue: "visageRightEyeClosedNotification"), object: nil)
    private let visageRightEyeOpenNotification = NSNotification(name: NSNotification.Name(rawValue: "visageRightEyeOpenNotification"), object: nil)
    
    //Private variables that cannot be accessed by other classes in any way.
    private var faceDetector : CIDetector?
    private var videoDataOutput : AVCaptureVideoDataOutput?
    private var videoDataOutputQueue : DispatchQueue?
    private var cameraPreviewLayer : AVCaptureVideoPreviewLayer?
    private var captureSession : AVCaptureSession = AVCaptureSession()
    private let notificationCenter : NotificationCenter = NotificationCenter.default
    private var currentOrientation : Int?
    
    init(cameraPosition : CameraDevice, optimizeFor : DetectorAccuracy) {
        super.init()
        
        currentOrientation = convertOrientation(deviceOrientation: UIDevice.current.orientation)
        
        switch cameraPosition {
        case .FaceTimeCamera : self.captureSetup(position: AVCaptureDevicePosition.front)
        case .ISightCamera : self.captureSetup(position: AVCaptureDevicePosition.back)
        }
        
        var faceDetectorOptions : [String : AnyObject]?
        
        switch optimizeFor {
        case .BatterySaving : faceDetectorOptions = [CIDetectorAccuracy : CIDetectorAccuracyLow as AnyObject]
        case .HigherPerformance : faceDetectorOptions = [CIDetectorAccuracy : CIDetectorAccuracyHigh as AnyObject]
        }
        
        self.faceDetector = CIDetector(ofType: CIDetectorTypeFace, context: nil, options: faceDetectorOptions)
    }
    
    //MARK: SETUP OF VIDEOCAPTURE
    func beginFaceDetection() {
        self.captureSession.startRunning()
    }
    
    func endFaceDetection() {
        self.captureSession.stopRunning()
    }
    
    private func captureSetup (position : AVCaptureDevicePosition) {
        var captureError : NSError?
        var captureDevice : AVCaptureDevice!
        
        for testedDevice in AVCaptureDevice.devices(withMediaType: AVMediaTypeVideo){
            if ((testedDevice as AnyObject).position == position) {
                captureDevice = testedDevice as! AVCaptureDevice
            }
        }
        
        if (captureDevice == nil) {
            captureDevice = AVCaptureDevice.defaultDevice(withMediaType: AVMediaTypeVideo)
        }
        
        var deviceInput : AVCaptureDeviceInput?
        do {
            deviceInput = try AVCaptureDeviceInput(device: captureDevice)
        } catch let error as NSError {
            captureError = error
            deviceInput = nil
        }
        captureSession.sessionPreset = AVCaptureSessionPresetHigh
        
        if (captureError == nil) {
            if (captureSession.canAddInput(deviceInput)) {
                captureSession.addInput(deviceInput)
            }
            
            self.videoDataOutput = AVCaptureVideoDataOutput()
            self.videoDataOutput!.videoSettings = [kCVPixelBufferPixelFormatTypeKey as AnyHashable: Int(kCVPixelFormatType_32BGRA)]
            self.videoDataOutput!.alwaysDiscardsLateVideoFrames = true
            self.videoDataOutputQueue = DispatchQueue(label:"VideoDataOutputQueue")
            self.videoDataOutput!.setSampleBufferDelegate(self, queue: self.videoDataOutputQueue!)
            
            if (captureSession.canAddOutput(self.videoDataOutput)) {
                captureSession.addOutput(self.videoDataOutput)
            }
        }
        
        visageCameraView.frame = UIScreen.main.bounds

		let previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer?.frame = UIScreen.main.bounds
        previewLayer?.videoGravity = AVLayerVideoGravityResizeAspectFill
        visageCameraView.layer.addSublayer(previewLayer!)
    }
    
    var options : [String : AnyObject]?
    
    //MARK: CAPTURE-OUTPUT/ANALYSIS OF FACIAL-FEATURES
    func captureOutput(_ captureOutput: AVCaptureOutput!, didOutputSampleBuffer sampleBuffer: CMSampleBuffer!, from connection: AVCaptureConnection!) {
        
        let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)
        let opaqueBuffer = Unmanaged<CVImageBuffer>.passUnretained(imageBuffer!).toOpaque()
        let pixelBuffer = Unmanaged<CVPixelBuffer>.fromOpaque(opaqueBuffer).takeUnretainedValue()
        let sourceImage = CIImage(cvPixelBuffer: pixelBuffer, options: nil)
        options = [CIDetectorSmile : true as AnyObject, CIDetectorEyeBlink: true as AnyObject, CIDetectorImageOrientation : 6 as AnyObject]
        
        let features = self.faceDetector!.features(in: sourceImage, options: options)
        
        if (features.count != 0) {
            
            if (onlyFireNotificatonOnStatusChange == true) {
                if (self.faceDetected == false) {
                    notificationCenter.post(visageFaceDetectedNotification as Notification)
                }
            } else {
                notificationCenter.post(visageFaceDetectedNotification as Notification)
            }
            
            self.faceDetected = true
            
            for feature in features as! [CIFaceFeature] {
                faceBounds = feature.bounds
                
                if (feature.hasFaceAngle) {
                    
                    if (faceAngle != nil) {
                        faceAngleDifference = CGFloat(feature.faceAngle) - faceAngle!
                    } else {
                        faceAngleDifference = CGFloat(feature.faceAngle)
                    }
                    
                    faceAngle = CGFloat(feature.faceAngle)
                }
                
                if (feature.hasLeftEyePosition) {
                    leftEyePosition = feature.leftEyePosition
                }
                
                if (feature.hasRightEyePosition) {
                    rightEyePosition = feature.rightEyePosition
                }
                
                if (feature.hasMouthPosition) {
                    mouthPosition = feature.mouthPosition
                }
                
                if (feature.hasSmile) {
                    if (onlyFireNotificatonOnStatusChange == true) {
                        if (self.hasSmile == false) {
                            notificationCenter.post(visageSmilingNotification as Notification)
                        }
                    } else {
                        notificationCenter.post(visageSmilingNotification as Notification)
                    }
                    
                    hasSmile = feature.hasSmile
                    
                } else {
                    if (onlyFireNotificatonOnStatusChange == true) {
                        if (self.hasSmile == true) {
                            notificationCenter.post(visageNotSmilingNotification as Notification)
                        }
                    } else {
                        notificationCenter.post(visageNotSmilingNotification as Notification)
                    }
                    
                    hasSmile = feature.hasSmile
                }
                
                if (feature.leftEyeClosed || feature.rightEyeClosed) {
                    if (onlyFireNotificatonOnStatusChange == true) {
                        if (self.isWinking == false) {
                            notificationCenter.post(visageWinkingNotification as Notification)
                        }
                    } else {
                        notificationCenter.post(visageWinkingNotification as Notification)
                    }
                    
                    isWinking = true
                    
                    if (feature.leftEyeClosed) {
                        if (onlyFireNotificatonOnStatusChange == true) {
                            if (self.leftEyeClosed == false) {
                                notificationCenter.post(visageLeftEyeClosedNotification as Notification)
                            }
                        } else {
                            notificationCenter.post(visageLeftEyeClosedNotification as Notification)
                        }
                        
                        leftEyeClosed = feature.leftEyeClosed
                    }
                    if (feature.rightEyeClosed) {
                        if (onlyFireNotificatonOnStatusChange == true) {
                            if (self.rightEyeClosed == false) {
                                notificationCenter.post(visageRightEyeClosedNotification as Notification)
                            }
                        } else {
                            notificationCenter.post(visageRightEyeClosedNotification as Notification)
                        }
                        
                        rightEyeClosed = feature.rightEyeClosed
                    }
                    if (feature.leftEyeClosed && feature.rightEyeClosed) {
                        if (onlyFireNotificatonOnStatusChange == true) {
                            if (self.isBlinking == false) {
                                notificationCenter.post(visageBlinkingNotification as Notification)
                            }
                        } else {
                            notificationCenter.post(visageBlinkingNotification as Notification)
                        }
                        
                        isBlinking = true
                    }
                } else {
                    
                    if (onlyFireNotificatonOnStatusChange == true) {
                        if (self.isBlinking == true) {
                            notificationCenter.post(visageNotBlinkingNotification as Notification)
                        }
                        if (self.isWinking == true) {
                            notificationCenter.post(visageNotWinkingNotification as Notification)
                        }
                        if (self.leftEyeClosed == true) {
                            notificationCenter.post(visageLeftEyeOpenNotification as Notification)
                        }
                        if (self.rightEyeClosed == true) {
                            notificationCenter.post(visageRightEyeOpenNotification as Notification)
                        }
                    } else {
                        notificationCenter.post(visageNotBlinkingNotification as Notification)
                        notificationCenter.post(visageNotWinkingNotification as Notification)
                        notificationCenter.post(visageLeftEyeOpenNotification as Notification)
                        notificationCenter.post(visageRightEyeOpenNotification as Notification)
                    }
                    
                    isBlinking = false
                    isWinking = false
                    leftEyeClosed = feature.leftEyeClosed
                    rightEyeClosed = feature.rightEyeClosed
                }
            }
        } else {
            if (onlyFireNotificatonOnStatusChange == true) {
                if (self.faceDetected == true) {
                    notificationCenter.post(visageNoFaceDetectedNotification as Notification)
                }
            } else {
                notificationCenter.post(visageNoFaceDetectedNotification as Notification)
            }
            
            self.faceDetected = false
        }
    }
    
    //TODO: 🚧 HELPER TO CONVERT BETWEEN UIDEVICEORIENTATION AND CIDETECTORORIENTATION 🚧
    private func convertOrientation(deviceOrientation: UIDeviceOrientation) -> Int {
        var orientation: Int = 0
        switch deviceOrientation {
        case .portrait:
            orientation = 6
        case .portraitUpsideDown:
            orientation = 2
        case .landscapeLeft:
            orientation = 3
        case .landscapeRight:
            orientation = 4
        default : orientation = 1
        }
        return orientation
    }
}
