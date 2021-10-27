import Foundation
import Promises
import WebRTC
import Starscream

class SignalClient: MulticastDelegate<SignalClientDelegate> {

    // connection state of WebSocket
    private(set) var connectionState: ConnectionState = .disconnected()
    private var webSocket: WebSocket?
    deinit {
        webSocket?.forceDisconnect()
        close()
    }
    
    func makeSocket(options: ConnectOptions, reconnect: Bool = false) {
        let rtcUrl = try! options.buildUrl(reconnect: reconnect)
        logger.debug("connecting with url: \(rtcUrl)")
        self.webSocket?.forceDisconnect()
        let webSocket = WebSocket(request: .init(url: rtcUrl))
        webSocket.delegate = self
        self.webSocket = webSocket
    }

    func connect(options: ConnectOptions, reconnect: Bool = false) -> Promise<Livekit_JoinResponse> {
        Promise<Void> { () -> Void in
            self.makeSocket(options: options, reconnect: reconnect)
        }.then {
            self.connectAndWaitReceiveJoinResponse()
        }
    }
    
    func reconnect() -> Promise<Void> {
        .init { fulfill, reject in
            var delegate: SignalClientDelegateClosures?
            delegate = SignalClientDelegateClosures(didConnect: { _, _ in
                // wait until connected
                fulfill(())
                delegate = nil
            }, didFailConnection: { _, error in
                reject(error)
                delegate = nil
            })
            // not required to clean up since weak reference
            self.add(delegate: delegate!)
            self.webSocket?.connect()
        }
    }

    private func sendRequest(_ request: Livekit_SignalRequest) {

        guard case .connected = connectionState else {
            logger.error("could not send message, not connected")
            return
        }

        do {
            let msg = try request.serializedData()
            webSocket?.write(data: msg)
        } catch {
            logger.error("could not serialize data: \(error)")
        }
    }

    func close() {
        connectionState = .disconnected()
        webSocket?.forceDisconnect()
        webSocket = nil
    }

    // handle errors after already connected
    private func handleError(_ reason: String) {
        notify { $0.signalClient(self, didClose: reason, code: 0) }
        close()
    }

    private func handleSignalResponse(msg: Livekit_SignalResponse.OneOf_Message) {

        guard case .connected = connectionState else {
            logger.error("not connected")
            return
        }

        do {
            switch msg {
            case let .join(joinResponse) :
                notify { $0.signalClient(self, didReceive: joinResponse) }

            case let .answer(sd):
                try notify { $0.signalClient(self, didReceiveAnswer: try sd.toRTCType()) }

            case let .offer(sd):
                try notify { $0.signalClient(self, didReceiveOffer: try sd.toRTCType()) }

            case let .trickle(trickle):
                let rtcCandidate = try RTCIceCandidate(fromJsonString: trickle.candidateInit)
                notify { $0.signalClient(self, didReceive: rtcCandidate, target: trickle.target) }

            case let .update(update):
                notify { $0.signalClient(self, didUpdate: update.participants) }

            case let .trackPublished(trackPublished):
                notify { $0.signalClient(self, didPublish: trackPublished) }

            case let .speakersChanged(speakers):
                notify { $0.signalClient(self, didUpdate: speakers.speakers) }

            case let .mute(mute):
                notify { $0.signalClient(self, didUpdateRemoteMute: mute.sid, muted: mute.muted) }

            case .leave:
                notify { $0.signalClientDidLeave(self) }

            default:
                logger.warning("unsupported signal response type: \(msg)")
            }
        } catch {
            logger.error("could not handle signal response: \(error)")
        }
    }
}

// MARK: Wait extension

extension SignalClient {
    func connectAndWaitReceiveJoinResponse() -> Promise<Livekit_JoinResponse> {

        logger.debug("waiting for join response...")

        return Promise<Livekit_JoinResponse> { fulfill, _ in
            // create temporary delegate
            var delegate: SignalClientDelegateClosures?
            delegate = SignalClientDelegateClosures(didReceiveJoinResponse: { _, joinResponse in
                // wait until connected
                fulfill(joinResponse)
                delegate = nil
            })
            // not required to clean up since weak reference
            self.add(delegate: delegate!)
            self.webSocket?.connect()
        }
    }
}

// MARK: - Send methods

extension SignalClient {

    func sendOffer(offer: RTCSessionDescription) throws {
        logger.debug("[SignalClient] Sending offer")

        let r = try Livekit_SignalRequest.with {
            $0.offer = try offer.toPBType()
        }

        sendRequest(r)
    }

    func sendAnswer(answer: RTCSessionDescription) throws {
        logger.debug("[SignalClient] Sending answer")

        let r = try Livekit_SignalRequest.with {
            $0.answer = try answer.toPBType()
        }

        sendRequest(r)
    }

    func sendCandidate(candidate: RTCIceCandidate, target: Livekit_SignalTarget) throws {
        logger.debug("[SignalClient] Sending ICE candidate")

        let r = try Livekit_SignalRequest.with {
            $0.trickle = try Livekit_TrickleRequest.with {
                $0.target = target
                $0.candidateInit = try candidate.toLKType().toJsonString()
            }
        }

        sendRequest(r)
    }

    func sendMuteTrack(trackSid: String, muted: Bool) {
        logger.debug("[SignalClient] Sending mute for \(trackSid), muted: \(muted)")

        let r = Livekit_SignalRequest.with {
            $0.mute = Livekit_MuteTrackRequest.with {
                $0.sid = trackSid
                $0.muted = muted
            }
        }

        sendRequest(r)
    }

    func sendAddTrack(cid: String, name: String, type: Livekit_TrackType,
                      dimensions: Dimensions? = nil) {
        logger.debug("[SignalClient] Sending add track request")

        let r = Livekit_SignalRequest.with {
            $0.addTrack = Livekit_AddTrackRequest.with {
                $0.cid = cid
                $0.name = name
                $0.type = type
                if let dimensions = dimensions {
                    $0.width = UInt32(dimensions.width)
                    $0.height = UInt32(dimensions.height)
                }
            }
        }

        sendRequest(r)
    }

    func sendUpdateTrackSettings(sid: String, disabled: Bool, videoQuality: Livekit_VideoQuality) {
        logger.debug("[SignalClient] Sending update track settings")

        let r = Livekit_SignalRequest.with {
            $0.trackSetting = Livekit_UpdateTrackSettings.with {
                $0.trackSids = [sid]
                $0.disabled = disabled
                $0.quality = videoQuality
            }
        }

        sendRequest(r)
    }

    func sendUpdateSubscription(sid: String, subscribed: Bool, videoQuality: Livekit_VideoQuality) {
        logger.debug("[SignalClient] Sending update subscription")

        let r = Livekit_SignalRequest.with {
            $0.subscription = Livekit_UpdateSubscription.with {
                $0.trackSids = [sid]
                $0.subscribe = subscribed
            }
        }

        sendRequest(r)
    }

    func sendLeave() {
        logger.debug("[SignalClient] Sending leave")

        let r = Livekit_SignalRequest.with {
            $0.leave = Livekit_LeaveRequest()
        }

        sendRequest(r)
    }
}

extension SignalClient: WebSocketDelegate {
    func didReceive(event: WebSocketEvent, client: WebSocket) {
        switch event {
        case .connected(_):
            connectionState = .connected
            notify { $0.signalClient(self, didConnect: false) }
        case .disconnected(let reason, let code):
            let error = SignalClientError.socketError(reason, code)
            connectionState = .disconnected(error)
            notify { $0.signalClient(self, didFailConnection: error) }
        case .text(let message):
            handleReceiveMessage(msg: message)
        case .binary(let data):
            handleReceiveMessage(msg: data)
        case .error(let error):
            var realError: Error
            if let error = error {
                realError = error
            } else {
                realError = SignalClientError.socketError("could not connect", 0)
            }
            connectionState = .disconnected(realError)
            notify { $0.signalClient(self, didFailConnection: realError) }
        case .reconnectSuggested(let isConnecting):
            if !isConnecting {
                connectionState = .connected
            } else {
                connectionState = .connecting(isReconnecting: isConnecting)
            }
            notify { $0.signalClient(self, didConnect: isConnecting) }
        case .cancelled:
            connectionState = .disconnected(nil)
            notify({$0.signalClient(self, didClose: "", code: 0)})
        default:break
        }
    }
    
    func handleReceiveMessage(msg: Any) {
        var response: Livekit_SignalResponse?
        do {
            if let text = msg as? String {
                response = try Livekit_SignalResponse(jsonString: text)
            } else if let data = msg as? Data {
                response = try Livekit_SignalResponse(contiguousBytes: data)
            }
        } catch {
            logger.error("could not decode JSON message: \(error)")
            handleError(error.localizedDescription)
        }
        
        if let sigResp = response, let msg = sigResp.message {
            handleSignalResponse(msg: msg)
        }
    }
}
