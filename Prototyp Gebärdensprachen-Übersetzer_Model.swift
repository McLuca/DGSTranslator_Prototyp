//
//  TranslatorModel.swift
//  DGSTranslator
//
//  Created by Luca kleine Hillmann on 06.06.22.
//

import Foundation
import UIKit
import NaturalLanguage

enum LocationAreaName: String {
    case TopLeftCorner
    case TopRightCorner
    case BottomLeftCorner
    case BottomRightCorner
}

enum DGSOperation {
    case Verortung
    case Referenzierung
    case Überschreibung
}

enum Timevalue: String, CaseIterable {
    case Heute
    case Gestern
    case Vorgestern
}

/// Stellt ein Schlüssel-Wert-Paar bestehend aus einem Verortungsbereich als Schlüssel und einem optionalen Element als Wert dar
class LocationElement {
    
    /// Vertortungsbereich
    var locationName: LocationAreaName
    /// Optionales, bereits verortetes Element
    var value: String?
    
    init(locationName: LocationAreaName, value: String?) {
        self.locationName = locationName
        self.value = value
    }
}
 
final class TranslatorModel {
    
    static let singleton = TranslatorModel()
    
    /// Enthält die vier Schlüssel-Wert-Paare (verorteten Elemente)
    var locationElements: [LocationElement] = [
        LocationElement(locationName: .TopLeftCorner, value: nil),
        LocationElement(locationName: .TopRightCorner, value: nil),
        LocationElement(locationName: .BottomLeftCorner, value: nil),
        LocationElement(locationName: .BottomRightCorner, value: nil)
    ]
    
    /// Enthält das zuletzt gebärdete Wort
    var lastSignedWord: String? {
        didSet {
            print("Neuer zufälliger Wert in Variable lastSignedWord gesetzt: \(lastSignedWord)")
        }
    }
    
    /// Setzt im Rahmen des Testsfalls "Referenzierung mit Zeit" eine zufällig gewähltes Wort, welches eine Zeit beschreibt (bspw. "Vorgestern")
    func setRandomTimeValue() {
        lastSignedWord = Timevalue.allCases.randomElement()?.rawValue
    }
    
    /// Setzt im Rahmen der Testfälle "Referenzierung" und "Überschreibung" Standardwerte für bereits verortete Elemente im Gebärdenraum
    func setRandomLocatedElementsDefault() {
        for element in locationElements {
            element.value = DGSValueGenerator.singleton.getRandomValue()
        }
    }
    
    /// Setzt für die Anwendung der Tests ein zufällig gewähltes letztes Wort
    func setRandomLastSignedWord() {
        lastSignedWord = DGSValueGenerator.singleton.getRandomValue()
    }
    
        
    /// Verortet ein neues Element am Referenzierungspunkt
    func locateElement(location: LocationAreaName) {
        locationElements.first { element in
            return element.locationName == location
        }?.value = lastSignedWord
        
        print("Element \(lastSignedWord!) bei \(location.rawValue) verortet")
    }
    
    /// Gibt den im Rahmen der Referenzierung ein verortetes Element zurück
    func getLocatedElementValue(location: LocationAreaName) -> String {
        let value = locationElements.first { element in
            return element.locationName == location
        }?.value
        
        return value!
    }
    
    /// Rückgabe eines booleschen Wertes, ob ein übergebener Verortungsbereich ein verortetes Element besitzt
    func hasLocatedAreaElement(locatedArea: LocationAreaName) -> Bool {
        return locationElements.contains { element in
            return element.locationName == locatedArea && element.value != nil
        }
    }

    /// Rückgabe eines booleschen Wertes, ob das zuletzt gebärdete Wort den selben Wert wie ein Element eines übergebenen Verortungsbereichs besitzt
    func isLastSignedWordEqualToValueOfLocatedArea(locatedArea: LocationAreaName) -> Bool {
        
        let valueOfLocatedElement = locationElements.first { element in
            return element.locationName == locatedArea
        }?.value
        
        return lastSignedWord! == valueOfLocatedElement
        
    }
    
    /// Gibt abhängig zum Anwendungsfall den passenden DGS-Operator zurück, welcher angewendet werden soll
    func getMatchingDGSOperation(locatedArea: LocationAreaName) throws -> DGSOperation {
        
        
        // Wenn Wert des Verortungsbereichs == nil -> Verortung
        if !hasLocatedAreaElement(locatedArea: locatedArea) {
            return .Verortung
        }
        
        // Wenn Wert des Verortungsbereichs != nil && lastSignedWord == nil -> Referenzierung
        if hasLocatedAreaElement(locatedArea: locatedArea) && lastSignedWord == nil {
            return .Referenzierung
        }
        
        // Wenn Wert des Verortungsbereichs != nil && lastSignedWord != nil && Wert Verortungsbereich != lastSignedWord -> Überschreiben
        if hasLocatedAreaElement(locatedArea: locatedArea) && lastSignedWord != nil && !isLastSignedWordEqualToValueOfLocatedArea(locatedArea: locatedArea) {
            return .Überschreibung
        }
        
        fatalError()
    }

    /// Rückgabe eines booleschen Wertes, ob das zuletzt gebärdete Wort eine Zeitangabe als Wort (bspw. "Gestern") darstellt
    func isLastSignedWordTime() -> Bool {

        guard let lastSignedWord = lastSignedWord else {
            return false
        }
        
        /// Wortagger, welcher Zeitangaben (bspw. "Gestern", "Heute", "Vorgestern") in einem Satz feststellen kann
        let timeTagger = NLTagger(tagSchemes: [.lexicalClass])
        timeTagger.setGazetteers([GebaerdenTagger.timeGazetteer], for: .lexicalClass)
        timeTagger.setLanguage(.german, range: lastSignedWord.startIndex..<lastSignedWord.endIndex)
        timeTagger.string = lastSignedWord
        
        // Kategorisierung des zuletzt gebärdeten Wortes
        let (wordTag, _) = timeTagger.tag(at: lastSignedWord.startIndex, unit: .word, scheme: .lexicalClass)
        
        if wordTag?.rawValue == "Zeit" {
            return true
        } else{
            return false
        }
    }
    
    
}
