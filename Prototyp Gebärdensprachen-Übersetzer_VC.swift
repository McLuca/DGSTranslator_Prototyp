//
//  TranslatorController.swift
//  DGSTranslator
//
//  Created by Luca kleine Hillmann on 05.06.22.
//

import Foundation
import UIKit
import AVFoundation
import Vision

final class TranslatorController: UIViewController {
    
    @IBOutlet weak var translatorPreview: UIView!
    @IBOutlet weak var translatorTextView: UITextView!
    
    fileprivate var cameraPreview = TranslatorView()
    fileprivate var gebaerdenDetector = GebeardenDetector()
    fileprivate let captureSession = AVCaptureSession()
    
    private var locatedArea: LocationAreaName? {
        didSet {
            print("Arealname gesetzt: \(locatedArea?.rawValue)\n")
        }
    }
    
    private var frameCounter: Int = 0
    private var frameCounterMaxSize: Int = 30
    
    private let _model = TranslatorModel.singleton
    private let dgsValueGenerator = DGSValueGenerator.singleton
 
    private let cameraDispatchQueue = DispatchQueue(label: "CAMERA_OutputQueue", qos: .userInteractive)
    private let dgsDispatchQueue = DispatchQueue(label: "DGS_DISPATCH_QUEUE", qos: .userInteractive)
    private let dispatchGroup = DispatchGroup()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        switch GlobalValues.testcase {
        case .Verortung:
            _model.setRandomLastSignedWord()
            
        case .ReferenzierungMitZeit:
            _model.setRandomTimeValue()
            _model.setRandomLocatedElementsDefault()
            setDefaultTranslatorText(testcase: .ReferenzierungMitZeit)
            
        case .ReferenzierungOhneZeit:
            _model.setRandomLocatedElementsDefault()
            setDefaultTranslatorText(testcase: .ReferenzierungOhneZeit)
            
        case .Überschreiben:
            _model.setRandomLocatedElementsDefault()
            _model.setRandomLastSignedWord()
        }
    
        
        switch AVCaptureDevice.authorizationStatus(for: .video) {
            
        case .authorized:
            break
            
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { response in
                if !response {
                    return
                }
            }
            
        case .denied:
            return
            
        case .restricted:
            return
            
        @unknown default:
            fatalError()
        }
        
        setupSession()
        
        if !captureSession.isRunning {
            DispatchQueue.main.async {
                self.captureSession.startRunning()
            }
        }
        
        cameraPreview.frame = translatorPreview.bounds
        translatorPreview.addSubview(cameraPreview)

    }
    
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
    }
    
    
    fileprivate func setupSession() {
        cameraPreview.previewLayer.session = captureSession
        captureSession.sessionPreset = .high
        
        guard let camera = AVCaptureDevice.default(.builtInTrueDepthCamera, for: .video, position: .front) else {
            return
        }
        
        do {
            let captureDeviceInput = try AVCaptureDeviceInput(device: camera)
            if captureSession.canAddInput(captureDeviceInput) {
                captureSession.addInput(captureDeviceInput)
            }
            
            let captureOutput = AVCaptureVideoDataOutput()
            captureOutput.alwaysDiscardsLateVideoFrames = true
            captureOutput.setSampleBufferDelegate(self, queue: cameraDispatchQueue)
            
            if captureSession.canAddOutput(captureOutput) {
                captureSession.addOutput(captureOutput)
            }
        }
        catch {
            fatalError()
        }
        
    }
    
    // Für den Anwendungsfall Referenzierung mit Zeit
    fileprivate func setDefaultTranslatorText(testcase: TestCase) {
        let valueElement = _model.locationElements.randomElement()!.value!
        
    
        DispatchQueue.main.async {
            
            switch testcase {
            
            case .ReferenzierungMitZeit:
                self.translatorTextView.text = "\(valueElement) [Verortung] Ich DGS lernen. \(self._model.lastSignedWord!)"
                
            case .ReferenzierungOhneZeit:
                self.translatorTextView.text = "\(valueElement) [Verortung] Ich DGS lernen."
                
            default:
                return
            }
            
            
        }
        
        
    }
    
    // -------------------------------------- DGS-Berechnungen ------------------------------------------
    
    
    /// Rückgabe des Verortungsbereichs, in dem zuvor die explizite Verortungsgestik ausgemacht wurde
    fileprivate func getAreaName(x: CGFloat, y: CGFloat) -> LocationAreaName {
        
        let viewframe = cameraPreview.frame
        
        if x < viewframe.midX && y < viewframe.midY {
            return .TopLeftCorner
        }
        else if x > viewframe.midX && y < viewframe.midY {
            return .TopRightCorner
        }
        else if x < viewframe.midX && y > viewframe.midY {
            return .BottomLeftCorner
        }
        else {
            return .BottomRightCorner
        }
        
    }
    
    
    
    /// Setzt den Verortungsbereich, in welcher die Veortungsgestik stattgefunden hat
    fileprivate func setDGSLocationArea(observation: VNHumanHandPoseObservation) {
        
        print("Start Berechnung Areal\n")
        
        // Koordinaten der Verortungsgestik anfragen, um den Verortungsbereich zu identifizieren
        guard let fingertipCoordinates = gebaerdenDetector.getCoordinatesOfIndexTip(observation: observation) else {
            print("Areal-Abbruch: Koordinaten der Zeigefingerspitze nicht erhältlich")
            locatedArea = nil
            dispatchGroup.leave()
            return
        }
        
        
        // Setzen des Verortungsbereichs in Anlehnung an die Koordinaten des Zeigefingers
        DispatchQueue.main.async {
            let coordinate = self.cameraPreview.previewLayer.layerPointConverted(fromCaptureDevicePoint: fingertipCoordinates)
            self.locatedArea = self.getAreaName(x: coordinate.x, y: coordinate.y)
            print("Ende Berechnung Areal\n")
            self.dispatchGroup.leave()
        }
    }
    
    /// Rückgabe eines booleschen Wertes über die Exisitenz einer vorliegenden gebärdeten Verortungsgestik innerhalb eines Frames
    fileprivate func modelMadeLocationPrediction(multiArray: MLMultiArray) -> Bool {
        /// Prediction war unter 0.7%
        guard let prediction = gebaerdenDetector.detectLocationGebaerde(poses: multiArray) else {
            return false
        }
        return prediction == "Verortungsgestik"
    }
    
    
    fileprivate func refreshValueLabels() {
        DispatchQueue.main.async {
            self.cameraPreview.setTextValues()
        }
    }
    
    fileprivate func addWordToTranslationText(dgsOperation: DGSOperation, word: String) {
        
        DispatchQueue.main.async {
            
            switch dgsOperation {
            case .Verortung:
                self.translatorTextView.text += " \(word) [Verortung]"
                return
                
            case .Referenzierung:
                self.translatorTextView.text += " \(word) [Referenzierung]"
                return
                
            case .Überschreibung:
                self.translatorTextView.text += " \(word) [Überschreibung]"
                return
        
            }
        
        }
        
        
        
    }

}

extension TranslatorController: AVCaptureVideoDataOutputSampleBufferDelegate {
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        
        // Alle 2 Sekunden eine Prediction machen um den Scope nicht überschreiten (1,5 Sek bei 30FPS Aufnahme = 45 Frames Wartezeit)
        frameCounter += 1
        if frameCounter % frameCounterMaxSize != 0 {return}

        // Zurücksetzen des Framecounters
        frameCounter = 0
        
        // Koordinaten der Handpose berechnen
        guard let handObservation = gebaerdenDetector.getHandPoseObservation(buffer: sampleBuffer) else {
            return
        }
        
        do {
            let keypointsMultiarray = try handObservation.keypointsMultiArray()
            
            // Abfrage über das Vorliegen einer Verortungsgestik im Frame
            if modelMadeLocationPrediction(multiArray: keypointsMultiarray) {
                print("------------------------------")
                print("Verortungsgestik wurde erkannt")
                dgsDispatchQueue.sync {
                    
                    dispatchGroup.enter()
                    
                    // Setzen der Area, an welcher die Verortungsgestik stattgefunden hat
                    setDGSLocationArea(observation: handObservation)
                    
                    // Wartet bis das zugehörige Areal berechnet wurde
                    dispatchGroup.wait()
                    
                    // Stoppt die Ausführung, falls kein Verortungsbereich gesetzt worden ist
                    if locatedArea == nil {
                        return
                    }
                    
                    // Überprüfung, ob das zuletzt gebärdete Wort einer Zeitangabe entspricht
                    // Wenn ja, so setze das zuletzt gebärdete Wort auf nil
                    if _model.isLastSignedWordTime() {
                        _model.lastSignedWord = nil
                    }
                    
                    // Feststellen, ob eine Verortung, Referenzierung oder eine Überschreibung vorliegt und die jeweilige Methode anwenden
                    
                    do {
                        switch try _model.getMatchingDGSOperation(locatedArea: locatedArea!) {
                            
                        case .Verortung:
                            print("Beginne Verortung")
                            _model.locateElement(location: locatedArea!)
                            refreshValueLabels()
                            addWordToTranslationText(dgsOperation: .Verortung, word: _model.lastSignedWord!)
                            print("Ende Verortung")
                            
                        case .Referenzierung:
                            print("Beginne Referenzierung")
                            
                            let valueOfArea = _model.getLocatedElementValue(location: locatedArea!)
                            
                            print("Referenzierung auf Wort \(valueOfArea) im Bereich \(locatedArea!.rawValue)")
                            addWordToTranslationText(dgsOperation: .Referenzierung, word: valueOfArea)
                            print("Ende Referenzierung")
                            
                        case .Überschreibung:
                            print("Beginne Überschreibung")
                            _model.locateElement(location: locatedArea!)
                            refreshValueLabels()
                            addWordToTranslationText(dgsOperation: .Überschreibung, word: _model.lastSignedWord!)
                            print("Ende Überschreibung")
                            
                        }
                        
                        switch GlobalValues.testcase {
                        case .ReferenzierungMitZeit:
                            _model.setRandomTimeValue()
                        
                        default:
                            _model.setRandomLastSignedWord()
                        }
                        
                        
                    } catch {
                        print("Error bei der Bestimmung des zuständigen DGS-Operators")
                    }
                    
                    
                }
                
            }
            
        }
        catch {fatalError()}
        
    }
    
}

