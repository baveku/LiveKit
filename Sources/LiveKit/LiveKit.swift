import Foundation
import Promises
import WebRTC

public class LiveKit {
    static let queue = DispatchQueue(label: "lk_queue")
    
    public static var isDebug: Bool {
        set {
            logger.isDebug = newValue
        }
        
        get {
            return logger.isDebug
        }
    }
}
