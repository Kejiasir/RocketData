// © 2016 LinkedIn Corp. All rights reserved.
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at  http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.

import Foundation
import ConsistencyManager

/**
 This class allows you to get a single callback whenever one or a few data providers get updated.
 First, the delegates of each of the data providers will be called.
 Then, the BatchDataProviderListenerDelegate method will be called.

 The main advantage of this class is to batch updates to these data providers.
 So if there is a change which affects data provider A and data provider B in different ways, there will still just be one callback to this listener.
 It will not call the batch data provider delegate twice for each data provider update; it will just call this delegate once.

 This is accomplished by creating a single combined model with all the data provider's models.
 This means that performance may be a bit worse since the models we're using will be larger.
 In general, you probably don't need to worry about this; it's just recommended you don't try to batch listen on every data provider in your app.
 The intended use case is when you have a view controller which has multiple data providers and wants to update in just one place.
 */
public class BatchDataProviderListener: BatchListenerDelegate {

    /// You must assign a delegate if you want a callback when one of the data providers gets updated
    public weak var delegate: BatchDataProviderListenerDelegate?

    /// The consistency manager which is backed by this instance
    public let consistencyManager: ConsistencyManager

    /// This is the batch listener from the consistency manager which contains most of the logic for doing batch listening
    private let batchListener: BatchListener

    /**
     Determines whether the listener is notified when data changes.
     When the the listener is paused, the data providers' data will not change unless setData is called on them directly.
     Changes that happen while the batch listener is paused will be queued and applied when the batch listener is unpaused.
     */
    public var paused: Bool {
        get {
            return consistencyManager.isPaused(batchListener)
        }
        set {
            if newValue {
                consistencyManager.pauseListeningForUpdates(batchListener)
            } else {
                // Do this before resuming with the consistency manager to give data providers a chance to update their models before we call currentModel
                batchListener.listeners.forEach { listener in
                    (listener as? BatchListenable)?.batchDataProviderUnpausedDataProvider()
                }
                consistencyManager.resumeListeningForUpdates(batchListener)
            }
        }
    }

    /**
     Designated initializer.

     - parameter dataProvider: The data providers you want to batch listen on. Should be a DataProvider or a CollectionDataProvider.
     - parameter dataModelManager: The DataModelManager which you are using to back these data providers.
     */
    public init(dataProviders: [protocol<ConsistencyManagerListener, BatchListenable>], dataModelManager: DataModelManager) {
        let listeners = dataProviders.map { $0 as ConsistencyManagerListener }
        batchListener = BatchListener(listeners: listeners, consistencyManager: dataModelManager.consistencyManager)
        consistencyManager = dataModelManager.consistencyManager
        batchListener.delegate = self
        batchListener.listenForUpdates(consistencyManager)

        for dataProvider in dataProviders {
            Log.sharedInstance.assert(dataProvider.batchListener == nil, "Data providers can only be assigned one batch listener. You cannot add the same data provider to two batch listeners.")
            dataProvider.batchListener = self
        }
    }

    // MARK: Internal

    /**
     Data providers need to call this method whenever their model is manually changed.
     */
    func listenerHasUpdatedModel(listener: ConsistencyManagerListener) {
        batchListener.listenerHasUpdatedModel(listener, consistencyManager: consistencyManager)
    }

    /**
     Data providers can call this whenever their model is changed if they want to specify a specific model which has changed.
     */
    func listenerHasUpdatedModel(model: ConsistencyManagerModel) {
        batchListener.listenerHasUpdatedModel(model, consistencyManager: consistencyManager)
    }

    /**
     This is the batch listener delegate method. It is only public because it's a requirement of the class.
     You should never call this directly.
     */
    public func batchListener(batchListener: BatchListener, hasUpdatedListeners listeners: [ConsistencyManagerListener], updates: ModelUpdates, context: Any?) {
        // Some data providers may have ignored the change because it's out of date
        // We'll exlude these from the updated list
        let listeners = listeners.filter { listener in
            if let listener = listener as? BatchListenable {
                return listener.syncedWithContext(context)
            }
            // Only remove it if we're sure we can remove it
            return true
        }
        if listeners.count > 0 {
            delegate?.batchDataProviderListener(self, hasUpdatedDataProviders: listeners, context: ConsistencyContextWrapper.actualContextFromConsistencyManagerContext(context))
        }
    }
}

/**
 The delegate protocol for BatchDataProviderListener.
 */
public protocol BatchDataProviderListenerDelegate: class {
    /**
     This is called at most once per consistency manager change.
     There may be several changes to each data provider.

     - parameter batchListener: The batch listener which reported the change.
     - parameter dataProviders: A list of data providers which have been updated.
     - parameter context: The context associated with this change.
     */
    func batchDataProviderListener(batchListener: BatchDataProviderListener, hasUpdatedDataProviders dataProviders: [ConsistencyManagerListener], context: Any?)
}

public protocol BatchListenable: class {
    /// Allows the batch listener to set and read this property
    weak var batchListener: BatchDataProviderListener? { get set }
    /**
     Returns true if the data provider actually updated to the current context.
     If the data provider ignored this change, the it will return false.
     */
    func syncedWithContext(context: Any?) -> Bool
    /**
     Called when a BatchDataProviderListener unpauses and before the consistency manager is notified.
     */
    func batchDataProviderUnpausedDataProvider()
}
