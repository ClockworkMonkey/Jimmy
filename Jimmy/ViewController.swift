//
//  ViewController.swift
//  Jimmy
//
//  Created by 王瑞果 on 2023/1/14.
//

import AVFoundation
import UIKit
import CoreMedia
import Vision
import VideoToolbox

class ViewController: UIViewController {

    @IBOutlet weak var previewView: UIView!
    
    private var videoViewLayer: CALayer! = nil
    private var previewLayer: AVCaptureVideoPreviewLayer! = nil
    private var captureSession = AVCaptureSession()
    private var captureVideoDataOutput = AVCaptureVideoDataOutput()
    private var bufferSize: CGSize = .zero
    private var visionRequests = [VNRequest]()
    private var objectIdentificationLayer: CALayer! = nil
    private let videoDataOutputQueue = DispatchQueue(label: "VideoDataOutputQueue", qos: .userInitiated, attributes: [], autoreleaseFrequency: .workItem)
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view.
        configureCaptureSession()
    }
    
    override func viewDidLayoutSubviews() {
        setupPreviewLayer()
        setupDectionLayer()
        setupVision()
    }

}

extension ViewController: AVCaptureVideoDataOutputSampleBufferDelegate {
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }
        let imageOrientation = getImagePropertyOrientation()
        let imageRequestHandler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: imageOrientation, options: [:])
        do {
            try imageRequestHandler.perform(self.visionRequests)
        } catch {
            print("------> " + "Error msg: " + error.localizedDescription)
        }
    }
    
}

extension ViewController {
    
    func configureCaptureSession() {
        // 视频输入
        let deviceInput: AVCaptureDeviceInput!
        let cptureDevice = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera], mediaType: .video, position: .back).devices.first
        guard let cptureDevice = cptureDevice else { return }
        do {
            deviceInput = try AVCaptureDeviceInput(device: cptureDevice)
        } catch {
            print("------> " + "Error msg: " + error.localizedDescription)
            return
        }
        
        captureSession.beginConfiguration()
        captureSession.sessionPreset = .vga640x480
        
        if captureSession.canAddInput(deviceInput) {
            captureSession.addInput(deviceInput)
        } else {
            captureSession.commitConfiguration()
            print("------> " + "Error msg: " + "Could not add vide input to the session.")
            return
        }
        
        // 视频输出
        if captureSession.canAddOutput(captureVideoDataOutput) {
            captureVideoDataOutput.alwaysDiscardsLateVideoFrames = true
            captureVideoDataOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange)]
            captureVideoDataOutput.setSampleBufferDelegate(self, queue: videoDataOutputQueue)
            captureSession.addOutput(captureVideoDataOutput)
        } else {
            captureSession.commitConfiguration()
            print("------> " + "Error msg: " + "Could not add vide data output to the session.")
            return
        }
        let captureConnection = captureVideoDataOutput.connection(with: .video)
        captureConnection?.isEnabled = true
        
        do {
            try cptureDevice.lockForConfiguration()
            let dimensions = CMVideoFormatDescriptionGetDimensions(cptureDevice.activeFormat.formatDescription)
            bufferSize.width = CGFloat(dimensions.width)
            bufferSize.height = CGFloat(dimensions.height)
            cptureDevice.unlockForConfiguration()
        } catch {
            print("------> " + "Error msg: " + error.localizedDescription)
        }
        captureSession.commitConfiguration()
    }
    
    func setupPreviewLayer() {
        // 视频预览
        previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.connection?.videoOrientation = .portrait
        videoViewLayer = previewView.layer
        previewLayer.frame = CGRect(origin: .zero, size: videoViewLayer.bounds.size)
        videoViewLayer.addSublayer(previewLayer)
        
        DispatchQueue.global(qos: .background).async {
            self.captureSession.startRunning()
        }
    }
    
}

extension ViewController {
    
    /*
     初始化视觉识别
     */
    @discardableResult
    func setupVision() -> NSError? {
        let error: NSError! = nil
        
        guard let mlModelURL = Bundle.main.url(forResource: "yolov5s", withExtension: "mlmodelc") else {
            return NSError(domain: "ViewController", code: -1, userInfo: [NSLocalizedDescriptionKey: "Model file is missing!"])
        }
        do {
            let mlModel = try VNCoreMLModel(for: MLModel(contentsOf: mlModelURL))
            let imageBasedRequest = VNCoreMLRequest(model: mlModel) { request, error in
                DispatchQueue.main.async {
                    if let observationRequest = request.results {
                        self.drawVisonRequestResults(observationRequest)
                    }
                }
            }
            self.visionRequests = [imageBasedRequest]
        } catch {
            print("------> " + "Error msg: " + error.localizedDescription)
        }
        return error
    }
    
    /*
     识别结果
     */
    func drawVisonRequestResults(_ results: [Any]) {
        CATransaction.begin()
        CATransaction.setValue(kCFBooleanTrue, forKey: kCATransactionDisableActions)
        objectIdentificationLayer.sublayers = nil
        for observation in results where observation is VNRecognizedObjectObservation {
            guard let objectObservation = observation as? VNRecognizedObjectObservation else { continue }
            let topLableObservation = objectObservation.labels[0]
            let objectBounds = VNImageRectForNormalizedRect(objectObservation.boundingBox, Int(bufferSize.width), Int(bufferSize.height))
            let shapeLayer = self.createRoundedRectLayer(with: objectBounds)
            let textLayer = self.createTextSubLayer(in: objectBounds, identifer: topLableObservation.identifier, confidence: topLableObservation.confidence)
            shapeLayer.addSublayer(textLayer)
            objectIdentificationLayer.addSublayer(shapeLayer)
        }
        self.updateObjectIdentificationLayer()
        CATransaction.commit()
    }
    
    func updateObjectIdentificationLayer() {
        let bounds = videoViewLayer.bounds
        var scale: CGFloat
        let xScale: CGFloat = bounds.size.width / bufferSize.height
        let yScale: CGFloat = bounds.size.height / bufferSize.width
        scale = fmax(xScale, yScale)
        if scale.isInfinite {
            scale = 1.0
        }
        CATransaction.begin()
        CATransaction.setValue(kCFBooleanTrue, forKey: kCATransactionDisableActions)
        objectIdentificationLayer.setAffineTransform(CGAffineTransform(rotationAngle: CGFloat(.pi / 2.0)).scaledBy(x: scale, y: -scale))
        objectIdentificationLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
        CATransaction.commit()
    }
    
    /*
     被识别物体图层
     */
    func setupDectionLayer() {
        objectIdentificationLayer = CALayer()
        objectIdentificationLayer.name = "Object Identification Layer"
        objectIdentificationLayer.bounds = CGRect(origin: .zero, size: bufferSize)
        objectIdentificationLayer.position = CGPoint(x: videoViewLayer.bounds.midX, y: videoViewLayer.bounds.midY)
        videoViewLayer.addSublayer(objectIdentificationLayer)
    }
    
    /*
     添加被识别物体轮廓
     */
    func createRoundedRectLayer(with bounds: CGRect) -> CALayer {
        let shaperLayer = CALayer()
        shaperLayer.name = "Object Rect Layer"
        shaperLayer.bounds = bounds
        shaperLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
        shaperLayer.backgroundColor = CGColor(colorSpace: CGColorSpaceCreateDeviceRGB(), components: [1.0, 1.0, 0.2, 0.4])
        shaperLayer.cornerRadius = 7
        return shaperLayer
    }
    
    /*
     添加被识别物体标签
     */
    func createTextSubLayer(in bounds: CGRect, identifer: String, confidence: VNConfidence) -> CATextLayer {
        let textLayerSize = CGSize(width: 70.0, height: 25.0)
        let textLayer = CATextLayer()
        textLayer.name = "Object Lable Layer"
        textLayer.string = String(format: "物体：\(identifer)\n相似度：%.2f", confidence)
        textLayer.fontSize = 8.0
        textLayer.bounds = CGRect(origin: .zero, size: textLayerSize)
        textLayer.position = CGPoint(x: bounds.origin.x - textLayerSize.height / 2, y: bounds.origin.y + textLayerSize.width / 2)
        textLayer.shadowOpacity = 0.7
        textLayer.shadowOffset = CGSize(width: 2.0, height: 2.0)
        textLayer.foregroundColor = CGColor(colorSpace: CGColorSpaceCreateDeviceRGB(), components: [0.0, 0.0, 0.0, 1.0])
        textLayer.backgroundColor = CGColor(colorSpace: CGColorSpaceCreateDeviceRGB(), components: [1.0, 1.0, 0.9, 0.4])
        textLayer.contentsScale = 2.0
        textLayer.setAffineTransform(CGAffineTransform(rotationAngle: CGFloat(.pi / 2.0)).scaledBy(x: 1.0, y: -1.0))
        return textLayer
    }
    
    public func getImagePropertyOrientation() -> CGImagePropertyOrientation {
        let deviceOrientation = UIDevice.current.orientation
        let imageOrientation: CGImagePropertyOrientation
        switch deviceOrientation {
        case .portraitUpsideDown:
            imageOrientation = .left
        case .landscapeLeft:
            imageOrientation = .upMirrored
        case .landscapeRight:
            imageOrientation = .down
        case .portrait:
            imageOrientation = .up
        default:
            imageOrientation = .up
        }
        return imageOrientation
    }
}
