/// Copyright (c) 2019 Razeware LLC
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

import Foundation
import CallKit

class CallManager {
  
  var callsChangedHandler: (() -> Void)?
  private(set) var calls: [Call] = []
  private let callController = CXCallController()
  
  
  func callWithUUID(uuid: UUID) -> Call? {
    guard let index = calls.index(where: { $0.uuid == uuid }) else {
      return nil
    }
    return calls[index]
  }
  
  func add(call: Call) {
    calls.append(call)
    call.stateChanged = { [weak self] in
      guard let self = self else { return }
      self.callsChangedHandler?()
    }
    callsChangedHandler?()
  }
  
  func remove(call: Call) {
    guard let index = calls.index(where: { $0 === call }) else { return }
    calls.remove(at: index)
    callsChangedHandler?()
  }
  
  func removeAllCalls() {
    calls.removeAll()
    callsChangedHandler?()
  }
  
}


extension CallManager {
  
  func end(call: Call) {
    
    // 1. Create an End call action. Pass in the call’s UUID to the initializer so it can be identified later.
    let endCallAction = CXEndCallAction(call: call.uuid)
    
    // 2. Wrap the action into a transaction so you can send it to the system.
    let transaction = CXTransaction(action: endCallAction)
    
    requestTransaction(transaction)
  }
  
  // 3. Invoke request(_:completion:) from the call controller. The system will request that the provider perform this transaction, which will in turn invoke the delegate method you just implemented.
  private func requestTransaction(_ transaction: CXTransaction) {
    
    callController.request(transaction) { error in
      if let error = error {
        print("Error requesting transaction: \(error)")
      } else {
        print("Requested transaction successfully")
      }
    }
    
  }
  
  func setHeld(call: Call, onHold: Bool) {
    
    let setHeldCallAction = CXSetHeldCallAction(call: call.uuid, onHold: onHold)
    let transaction = CXTransaction()
    transaction.addAction(setHeldCallAction)
    
    requestTransaction(transaction)
  }
  
  func startCall(handle: String, videoEnabled: Bool) {
    
    // 1 A handle, represented by CXHandle, can specify the handle type and its value. Hotline supports phone number handles, so you’ll use it here as well.
    let handle = CXHandle(type: .phoneNumber, value: handle)
    
    // 2 A CXStartCallAction receives a unique UUID and a handle as input.
    let startCallAction = CXStartCallAction(call: UUID(), handle: handle)
    
    // 3 Specify whether the call is audio-only or a video call by setting the isVideo property of the action.
    startCallAction.isVideo = videoEnabled
    let transaction = CXTransaction(action: startCallAction)
    
    requestTransaction(transaction)
  }
  
  
}
