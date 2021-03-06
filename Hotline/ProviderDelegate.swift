/// Copyright (c) 2020 Razeware LLC
/// 
/// Permission is hereby granted, free of charge, to any person obtaining a copy
/// of this software and associated documentation files (the "Software"), to deal
/// in the Software without restriction, including without limitation the rights
/// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
/// copies of the Software, and to permit persons to whom the Software is
/// furnished to do so, subject to the following conditions:
/// 
/// The above copyright notice and this permission notice shall be included in
/// all copies or substantial portions of the Software.
/// 
/// Notwithstanding the foregoing, you may not use, copy, modify, merge, publish,
/// distribute, sublicense, create a derivative work, and/or sell copies of the
/// Software in any work that is designed, intended, or marketed for pedagogical or
/// instructional purposes related to programming, coding, application development,
/// or information technology.  Permission for such use, copying, modification,
/// merger, publication, distribution, sublicensing, creation of derivative works,
/// or sale is expressly withheld.
/// 
/// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
/// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
/// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
/// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
/// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
/// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
/// THE SOFTWARE.

import AVFoundation
import CallKit

class ProviderDelegate: NSObject {
    
    // 1. Store references to both the provider and the call controller. The provider delegate will interact with both of them.
    private let callManager: CallManager
    private let provider: CXProvider
    
    init(callManager: CallManager) {
        self.callManager = callManager
        
        // 2. Initialize the provider with the appropriate CXProviderConfiguration, stored as a static variable below. A provider configuration specifies the behavior and capabilities of the calls.
        provider = CXProvider(configuration: ProviderDelegate.providerConfiguration)
        
        super.init()
        
        // 3. Set the delegate to respond to events coming from the provider.
        provider.setDelegate(self, queue: nil)
    }
    
    // 4. In the case of Hotline, the provider configuration allows video calls and phone number handles and restricts the number of call groups to one. For further customization, refer to the CallKit documentation.
    static var providerConfiguration: CXProviderConfiguration = {
        let providerConfiguration = CXProviderConfiguration(localizedName: "Hotline")
        
        providerConfiguration.supportsVideo = true
        providerConfiguration.maximumCallsPerCallGroup = 1
        providerConfiguration.supportedHandleTypes = [.phoneNumber]
        
        return providerConfiguration
    }()
}


extension ProviderDelegate {
    
    // This helper method allows the app to call the CXProvider API to report an incoming call.
    func reportIncomingCall(
        uuid: UUID,
        handle: String,
        hasVideo: Bool = false,
        completion: ((Error?) -> Void)?
    ) {
        
        // 1. Prepare a call update for the system which will contain the relevant call metadata.
        let update = CXCallUpdate()
        update.remoteHandle = CXHandle(type: .phoneNumber, value: handle)
        update.hasVideo = hasVideo
        
        // 2. Invoke reportNewIncomingCall(with:update:completion) on the provider to notify the system of the incoming call.
        provider.reportNewIncomingCall(with: uuid, update: update) { error in
            if error == nil {
                
                // 3. The completion handler will be called once the system processes the call. Assuming no errors, you create a Call instance and add it to the list of calls via the CallManager.
                let call = Call(uuid: uuid, handle: handle)
                self.callManager.add(call: call)
            }
            
            // 4. Invoke the completion handler if it’s not nil.
            completion?(error)
        }
    }
    
}

// MARK: - CXProviderDelegate
extension ProviderDelegate: CXProviderDelegate {
    
    func providerDidReset(_ provider: CXProvider) {
        stopAudio()
        
        for call in callManager.calls {
            call.end()
        }
        
        callManager.removeAllCalls()
    }
    
    func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
        // 1. A reference comes from the call manager, corresponding to the UUID of the call to answer.
        guard let call = callManager.callWithUUID(uuid: action.callUUID) else {
            action.fail()
            return
        }
        
        // 2. The app configures the audio session for the call. The system activates the session at an elevated priority.
        configureAudioSession()
        
        // 3. answer() indicates that the call is now active.
        call.answer()
        
        // 4. When processing an action, it’s important to either fail or fulfill it. Assuming no errors during the process, you can call fulfill() to indicate success.
        action.fulfill()
    }
    
    // 5. Once the system activates the provider’s audio session, the delegate is notified. This is your chance to begin processing the call’s audio.
    func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
        startAudio()
    }
    
    
    func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
        
        // 1. Start by getting a reference to the call from the call manager.
        guard let call = callManager.callWithUUID(uuid: action.callUUID) else {
            action.fail()
            return
        }
        
        // 2. As the call is about to end, it’s time to stop processing the call’s audio.
        stopAudio()
        
        // 3. Invoking end() changes the status of the call, allowing other classes to react to the new state.
        call.end()
        
        // 4. At this point, you’ll mark the action as fulfilled.
        action.fulfill()
        
        // 5. Since you no longer need the call, the call manager can dispose of it.
        callManager.remove(call: call)
        
    }
    
    
    func provider(_ provider: CXProvider, perform action: CXSetHeldCallAction) {
        guard let call = callManager.callWithUUID(uuid: action.callUUID) else {
            action.fail()
            return
        }
        
        // 1.  After getting the reference to the call, update its status according to the isOnHold property of the action.
        call.state = action.isOnHold ? .held : .active
        
        // 2. Depending on the status, start or stop processing the call’s audio.
        if call.state == .held {
            stopAudio()
        } else {
            startAudio()
        }
        
        // 3. Mark the action fulfilled.
        action.fulfill()
    }
    
    func provider(_ provider: CXProvider, perform action: CXStartCallAction) {
        
        let call = Call(uuid: action.callUUID, outgoing: true, handle: action.handle.value)
        
        // 1. After creating a Call with the call’s UUID from the call manager, you’ll have to configure the app’s audio session. Just as with incoming calls, your responsibility at this point is only configuration. The actual processing will start later, when provider(_:didActivate) is invoked.

        configureAudioSession()
        
        // 2. The delegate monitors the call’s lifecycle. It’ll initially report that the outgoing call has started connecting. When the call is connected, the provider delegate will report that as well.
        call.connectedStateChanged = { [weak self, weak call] in
            guard
                let self = self,
                let call = call
            else {
                return
            }
            
            if call.connectedState == .pending {
                self.provider.reportOutgoingCall(with: call.uuid, startedConnectingAt: nil)
            } else if call.connectedState == .complete {
                self.provider.reportOutgoingCall(with: call.uuid, connectedAt: nil)
            }
        }
        
        // 3. Calling start() on the call triggers its lifecycle changes. Upon a successful connection, the call can be marked as fulfilled.
        call.start { [weak self, weak call] success in
            guard
                let self = self,
                let call = call
            else {
                return
            }
            
            if success {
                action.fulfill()
                self.callManager.add(call: call)
            } else {
                action.fail()
            }
        }
    }
    
    
}




