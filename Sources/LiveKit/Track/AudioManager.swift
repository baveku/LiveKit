

/*
 * Copyright 2022 LiveKit
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import Foundation
import WebRTC

// Audio Session Configuration related
public class AudioManager: Loggable {

    // MARK: - Public
    public static let shared = AudioManager()
    public var preferSpeakerOutput: Bool = true

    #if os(iOS)
    private let notificationQueue = OperationQueue()
    private var routeChangeObserver: NSObjectProtocol?
    #endif

    // Singleton
    private init() {
        #if os(iOS)
        //
        routeChangeObserver = NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification,
                                                                     object: nil,
                                                                     queue: notificationQueue) { [weak self] notification in
            //
            guard let self = self else { return }
            self.log("AVAudioSession.routeChangeNotification \(String(describing: notification.userInfo))")

            guard let number = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? NSNumber?,
                  let uint = number?.uintValue,
                  let reason = AVAudioSession.RouteChangeReason(rawValue: uint)  else { return }

            switch reason {
            case .newDeviceAvailable:
                DispatchQueue.webRTC.async {
                    do {
                        let session = RTCAudioSession.sharedInstance()
                        try session.overrideOutputAudioPort(self.preferSpeakerOutput && !AVAudioSession.isHeadphonesConnected ? .speaker : .none)
                        try session.setActive(true)
                    } catch let error {
                        self.log("Failed to overrideOutputAudioPort with error: \(error)", .error)
                    }
                }
            default: break
            }
        }
        #endif
    }
    
    public func activeAudioSession() {
        #if os(iOS)
        DispatchQueue.webRTC.async { [weak self] in

            guard let self = self else { return }

            // prepare config
            let configuration = RTCAudioSessionConfiguration.webRTC()
            var categoryOptions: AVAudioSession.CategoryOptions = [.allowBluetooth, .allowBluetoothA2DP, .allowAirPlay]

            if self.preferSpeakerOutput {
                categoryOptions.insert(.defaultToSpeaker)
            }
            
            configuration.categoryOptions = [.allowBluetooth, .allowBluetoothA2DP, .allowBluetooth]
            configuration.mode = AVAudioSession.Mode.videoChat.rawValue
            

            // configure session
            let session = RTCAudioSession.sharedInstance()
            let setActive: Bool = session.mode != configuration.mode
            session.lockForConfiguration()
            // always unlock
            defer { session.unlockForConfiguration() }

            do {
                self.log("configuring audio session with category: \(configuration.category), mode: \(configuration.mode), setActive: \(String(describing: setActive))")
                if setActive {
                    try session.setConfiguration(configuration, active: setActive)
                    
                } else {
                    try session.setConfiguration(configuration)
                }
                try session.overrideOutputAudioPort(self.preferSpeakerOutput && !AVAudioSession.isHeadphonesConnected ? .speaker : .none)
            } catch let error {
                self.log("Failed to configureAudioSession with error: \(error)", .error)
            }
        }
        #endif
    }
    
    public func deactiveAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.soloAmbient, options: [.mixWithOthers])
            try session.setMode(.default)
            try session.setActive(true)
        } catch {}
    }

    deinit {
        #if os(iOS)
        // remove the route change observer
        if let observer = routeChangeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        #endif
    }
}

extension AVAudioSession {

    static var isHeadphonesConnected: Bool {
        return sharedInstance().isHeadphonesConnected
    }

    var isHeadphonesConnected: Bool {
        return !currentRoute.outputs.filter { $0.isHeadphones }.isEmpty
    }
}

extension AVAudioSessionPortDescription {
    var isHeadphones: Bool {
        return portType == .headphones || portType == .bluetoothHFP || portType == .bluetoothA2DP || portType == .bluetoothLE
    }
}
