//
//  SignalHandler.swift
//  promise-signals-ios
//
//  Created by Markus Gasser on 18.10.15.
//  Copyright © 2015 konoma GmbH. All rights reserved.
//

import Foundation
import PromiseKit


open class SignalHandler<T> {
    
    fileprivate typealias HandlerBlock = (Promise<T>) -> Void
    
    fileprivate let signalQueue: DispatchQueue
    fileprivate weak var signalChain: SignalChain?
    
    internal init(signalQueue: DispatchQueue, registerOnChain signalChain: SignalChain) {
        self.signalQueue = signalQueue
        self.signalChain = signalChain
        
        signalChain.registerSignalHandler(self)
    }
    
    
    // only access these vars from the signals queue
    fileprivate var currentPromise: Promise<T>?
    fileprivate var handlers = [HandlerBlock]()
    
    
    // MARK: - Notify Results
    
    internal func notifyNewPromise(_ promise: Promise<T>) {
        // must be called on the signal queue
        
        currentPromise = promise
        
        // apply all handler blocks to the new promise
        for handler in handlers {
            handler(promise)
        }
    }
    
    
    // MARK: - Promise Methods
    
    open func then<U>(on q: DispatchQueue = DispatchQueue.main, _ body: @escaping (T) throws -> Promise<U>) -> SignalHandler<U> {
        let signalHandler = SignalHandler<U>(signalQueue: signalQueue, registerOnChain: signalChain!)
        
        applyAndRegisterTransformer(nextHandler: signalHandler) { promise in
            return promise.then(on: q, body)
        }
        
        return signalHandler
    }
    
    open func then<U>(on q: DispatchQueue = DispatchQueue.main, _ body: @escaping (T) throws -> U) -> SignalHandler<U> {
        let signalHandler = SignalHandler<U>(signalQueue: signalQueue, registerOnChain: signalChain!)
        
        applyAndRegisterTransformer(nextHandler: signalHandler) { promise in
            return promise.then(on: q, body)
        }
        
        return signalHandler
    }
    
    open func thenInBackground<U>(_ body: @escaping (T) throws -> U) -> SignalHandler<U> {
        return then(on: DispatchQueue.global(qos: .background), body)
    }
    
    open func thenInBackground<U>(_ body: @escaping (T) throws -> Promise<U>) -> SignalHandler<U> {
        return then(on: DispatchQueue.global(qos: .background), body)
    }
    
    open func error(policy: ErrorPolicy = .AllErrorsExceptCancellation, _ body: @escaping (Error) -> Void) {
        applyAndRegisterTransformer { promise in
            promise.error(policy: policy, body)
        }
    }
    
    open func recover(on q: DispatchQueue = DispatchQueue.main, _ body: @escaping (Error) throws -> Promise<T>) -> SignalHandler<T> {
        let signalHandler = SignalHandler(signalQueue: signalQueue, registerOnChain: signalChain!)
        
        applyAndRegisterTransformer(nextHandler: signalHandler) { promise in
            return promise.recover(on: q, body)
        }
        
        return signalHandler
    }
    
    open func recover(on q: DispatchQueue = DispatchQueue.main, _ body: @escaping (Error) throws -> T) -> SignalHandler<T> {
        let signalHandler = SignalHandler(signalQueue: signalQueue, registerOnChain: signalChain!)
        
        applyAndRegisterTransformer(nextHandler: signalHandler) { promise in
            return promise.recover(on: q, body)
        }
        
        return signalHandler
    }
    
    open func always(on q: DispatchQueue = DispatchQueue.main, _ body: @escaping () -> Void) -> SignalHandler<T> {
        let signalHandler = SignalHandler(signalQueue: signalQueue, registerOnChain: signalChain!)
        
        applyAndRegisterTransformer(nextHandler: signalHandler) { promise in
            return promise.always(on: q, body)
        }
        
        return signalHandler
    }
    
    
    // MARK: - Helpers
    
    fileprivate func applyAndRegisterTransformer(_ transformer: @escaping (Promise<T>) -> Void) {
        let wrappedTransformer = { (promise: Promise<T>) -> Promise<Void>? in
            transformer(promise)
            return nil
        }
        
        applyAndRegisterTransformer(nextHandler: nil, transformer: wrappedTransformer)
    }

    fileprivate func applyAndRegisterTransformer<U>(nextHandler: SignalHandler<U>?, transformer: @escaping (Promise<T>) -> Promise<U>?) {
        onSignalsQueue {
            weak var weakChild = nextHandler
            
            // transform the promise and apply to a child if necessary
            let handlerBlock: HandlerBlock = { promise in
                if let childPromise = transformer(promise) {
                    weakChild?.notifyNewPromise(childPromise)
                }
            }
            
            // apply the handler block to the current promise if necessary
            if let promise = self.currentPromise {
                handlerBlock(promise)
            }
            
            // register the handler bock for future promise updates
            self.handlers.append(handlerBlock)
        }
    }
    
    fileprivate func onSignalsQueue(_ block: @escaping () -> Void) {
        signalQueue.async(execute: block)
    }
}