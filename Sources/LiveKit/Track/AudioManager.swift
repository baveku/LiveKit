

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

    public typealias ConfigureAudioSessionFunc = (_ newState: State,
                                                  _ oldState: State) -> Void

    /// Use this to provide a custom func to configure the audio session instead of ``defaultConfigureAudioSessionFunc(newState:oldState:)``.
    /// This method should not block and is expected to return immediately.
    public var customConfigureAudioSessionFunc: ConfigureAudioSessionFunc?

    public enum TrackState {
        case none
        case localOnly
        case remoteOnly
        case localAndRemote
    }

    public struct State {
        var localTracksCount: Int = 0
        var remoteTracksCount: Int = 0
    }

    public var localTracksCount: Int { _state.localTracksCount }
    public var remoteTracksCount: Int { _state.remoteTracksCount }

    // MARK: - Internal
    internal enum `Type` {
        case local
        case remote
    }

    // MARK: - Private
    private var _state = StateSync(State())
    private var _isActive = false

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
                    self.refreshAudioPort()
                }
            case .oldDeviceUnavailable:
                DispatchQueue.webRTC.async {
                    self.refreshAudioPort()
                }
            default: break
            }
        }
        #endif

        // trigger events when state mutates
        _state.onMutate = { [weak self] newState, oldState in
            guard let self = self, self._isActive else { return }
            self.configureAudioSession(newState: newState, oldState: oldState)
        }
    }

    deinit {
        #if os(iOS)
        // remove the route change observer
        if let observer = routeChangeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        #endif
    }

    internal func trackDidStart(_ type: Type) {
        // async mutation
        _state.mutateAsync { state in
            if type == .local { state.localTracksCount += 1 }
            if type == .remote { state.remoteTracksCount += 1 }
        }
    }

    internal func trackDidStop(_ type: Type) {
        // async mutation
        _state.mutateAsync { state in
            if type == .local { state.localTracksCount -= 1 }
            if type == .remote { state.remoteTracksCount -= 1 }
        }
    }

    private func configureAudioSession(newState: State, oldState: State) {

        log("\(oldState) -> \(newState)")

        #if os(iOS)
        if let customConfigureAudioSessionFunc = customConfigureAudioSessionFunc {
            customConfigureAudioSessionFunc(newState, oldState)
        } else {
            defaultConfigureAudioSessionFunc(newState: newState, oldState: oldState)
        }
        #endif
    }

    #if os(iOS)
    /// The default implementation when audio session configuration is requested by the SDK.
    /// Configure the `RTCAudioSession` of `WebRTC` framework.
    ///
    /// > Note: It is recommended to use `RTCAudioSessionConfiguration.webRTC()` to obtain an instance of `RTCAudioSessionConfiguration` instead of instantiating directly.
    ///
    /// - Parameters:
    ///   - configuration: A configured RTCAudioSessionConfiguration
    ///   - setActive: passing true/false will call `AVAudioSession.setActive` internally
    public func defaultConfigureAudioSessionFunc(newState: State, oldState: State) {
        guard _isActive else {return}
        DispatchQueue.webRTC.async { [weak self] in
            
            guard let self = self else { return }

            // prepare config
            let configuration = RTCAudioSessionConfiguration.webRTC()
            var categoryOptions: AVAudioSession.CategoryOptions = []

            switch newState.trackState {
            case .remoteOnly:
                configuration.category = AVAudioSession.Category.playback.rawValue
                configuration.mode = AVAudioSession.Mode.spokenAudio.rawValue
            case  .localOnly, .localAndRemote:
                configuration.category = AVAudioSession.Category.playAndRecord.rawValue
                configuration.mode = AVAudioSession.Mode.videoChat.rawValue

                categoryOptions = [.allowBluetooth, .allowBluetoothA2DP]

                if newState.preferSpeakerOutput {
                    categoryOptions.insert(.defaultToSpeaker)
                }

            default:
                configuration.category = AVAudioSession.Category.soloAmbient.rawValue
                configuration.mode = AVAudioSession.Mode.default.rawValue
            }

            configuration.categoryOptions = categoryOptions

            var setActive: Bool?
            if newState.trackState != .none, oldState.trackState == .none {
                // activate audio session when there is any local/remote audio track
                setActive = true
            } else if newState.trackState == .none, oldState.trackState != .none {
                // deactivate audio session when there are no more local/remote audio tracks
                setActive = false
            }

            // configure session
            let session = RTCAudioSession.sharedInstance()
            session.lockForConfiguration()
            // always unlock
            defer { session.unlockForConfiguration() }

            do {
                self.log("configuring audio session with category: \(configuration.category), mode: \(configuration.mode), setActive: \(String(describing: setActive))")

                if let setActive = setActive {
                    try session.setConfiguration(configuration, active: setActive)
                } else {
                    try session.setConfiguration(configuration)
                }

            } catch let error {
                self.log("Failed to configureAudioSession with error: \(error)", .error)
            }

            do {
                self.log("preferSpeakerOutput: \(newState.preferSpeakerOutput)")
                try session.overrideOutputAudioPort(newState.preferSpeakerOutput ? .speaker : .none)
            } catch let error {
                self.log("Failed to overrideOutputAudioPort with error: \(error)", .error)
            }

            if newState.trackState != .none {
                self.refreshAudioPort()
            }
        }
    }
    #endif
    
    func refreshAudioPort() {
        guard _isActive else {return}
        let session = RTCAudioSession.sharedInstance()
        do {
            try session.overrideOutputAudioPort(preferSpeakerOutput && !AVAudioSession.isHeadphonesConnected ? .speaker : .none)
        } catch let error {
            self.log("Failed to overrideOutputAudioPort with error: \(error)", .error)
        }
    }
    
    func startMonitoring() {
        DispatchQueue.webRTC.async {
            // prepare config
            let configuration = RTCAudioSessionConfiguration.webRTC()
            var categoryOptions: AVAudioSession.CategoryOptions = []
            configuration.category = AVAudioSession.Category.playAndRecord.rawValue
            categoryOptions = [.allowBluetooth, .allowBluetoothA2DP, .allowAirPlay]
            if self.preferSpeakerOutput {
                categoryOptions.insert(.defaultToSpeaker)
            }
            let session = RTCAudioSession.sharedInstance()
            session.lockForConfiguration()
            do {
                try session.setConfiguration(configuration, active: true)
            } catch let error {
                self.log("Failed to configureAudioSession with error: \(error)", .error)
            }
            session.unlockForConfiguration()
        }
        _isActive = true
    }
    
    func stopMonitoring() {
        _isActive = false
        deactivateRTCAudioSession()
    }
    
    func deactivateRTCAudioSession() {
        self._state.mutateAsync { state in
            state.localTracksCount = 0
            state.remoteTracksCount = 0
        }
        DispatchQueue.webRTC.async {
            let session = RTCAudioSession.sharedInstance()
            session.lockForConfiguration()
            do {
                try session.setActive(false)
            } catch let error {
                self.log("Failed to deactivateSession with error: \(error)", .error)
            }
            session.unlockForConfiguration()
        }
    }
}

extension AudioManager.State {

    public var trackState: AudioManager.TrackState {

        if localTracksCount > 0 && remoteTracksCount == 0 {
            return .localOnly
        } else if localTracksCount == 0 && remoteTracksCount > 0 {
            return .remoteOnly
        } else if localTracksCount > 0 && remoteTracksCount > 0 {
            return .localAndRemote
        }

        return .none
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
