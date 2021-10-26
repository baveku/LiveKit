//
//  Logger.swift
//  
//
//  Created by Bách on 26/10/2021.
//

import Foundation

let logger = Logger.shared
class Logger {
    static let shared = Logger()
    let dateFormatter = DateFormatter()
    var isDebug = false
    
    init() {
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
    }
    
    func debug(_ message: String) {
        printMsg(message, type: .DEBUG)
    }
    
    func error(_ message: String) {
        printMsg(message, type: .ERROR)
    }
    
    func warning(_ message: String) {
        printMsg(message, type: .WARNING)
    }
    
    func info(_ message: String) {
        printMsg(message, type: .INFO)
    }
    
    private func printMsg(_ msg: String, type: LogType = .DEBUG) {
        guard isDebug else {return}
        let dateNow = dateFormatter.string(from: Date())
        print("\(dateNow)||[LiveKit][\(type.rawValue)] \(msg)")
    }
    
    enum LogType: String {
        case DEBUG
        case WARNING
        case ERROR
        case INFO
        
    }
}
