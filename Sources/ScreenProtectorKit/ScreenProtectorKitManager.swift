//
//  ScreenProtectorKitManager.swift
//  ScreenProtectorKit
//
//  Created by INTENIQUETIC on 16/10/2568 BE.
//

/// ScreenProtectorKitManager provides a thread-safe interface for controlling screenshot prevention
/// and data leakage protection visuals (blur, image, color). It also supports state snapshotting
/// to copy configuration between instances and re-apply later.

import UIKit

/// Executes the given closure on the main thread. If already on main, runs immediately; otherwise dispatches asynchronously.
/// - Parameter work: The closure to execute on the main thread.
public func onMain(_ work: @escaping () -> Void) {
    if Thread.isMainThread { work() } else { DispatchQueue.main.async(execute: work) }
}

/// Represents the current operational state for a given protection feature.
public enum ProtectionState {
    case idle
    case on
    case off
}

/// Identifies a protection category used during app lifecycle transitions.
public enum ProtectionType {
    case screenshot
    case dataLeakage
}

/// Describes the outcome of attaching/removing an event listener.
public enum ListenerStatus: String, Equatable {
    case listened
    case removed
    case unsupported
}

/// Events that can be observed by the manager.
public enum ListenerEvent: Equatable {
    case screenshot
    case screenRecording
}

/// Payloads delivered to event listeners.
public enum ListenerPayload: Equatable {
    case screenshot
    case screenRecording(Bool)
}

/// Visual protection modes to reduce data leakage risk.
public enum ProtectionMode: Equatable {
    case none
    case blur
    case image(name: String)
    case color(hex: String)
}

/// Snapshot for exporting/importing manager state across instances.
/// Use with `getStateSnapshot()` and `setStateSnapshot(_:)`.
public struct StateSnapshot: Equatable {
    public var preventScreenshotState: ProtectionState
    public var blurProtectionState: ProtectionState
    public var imageProtectionState: ProtectionState
    public var colorProtectionState: ProtectionState
    public var imageProtectionName: String
    public var colorProtectionHex: String
    
    public init(preventScreenshotState: ProtectionState,
                blurProtectionState: ProtectionState,
                imageProtectionState: ProtectionState,
                colorProtectionState: ProtectionState,
                imageProtectionName: String,
                colorProtectionHex: String) {
        self.preventScreenshotState = preventScreenshotState
        self.blurProtectionState = blurProtectionState
        self.imageProtectionState = imageProtectionState
        self.colorProtectionState = colorProtectionState
        self.imageProtectionName = imageProtectionName
        self.colorProtectionHex = colorProtectionHex
    }
}

/// Abstraction for controlling screen protection features and listeners.
public protocol ScreenProtectorKitManaging: AnyObject {
    func applicationWillResignActive(_ type: ProtectionType)
    func applicationDidBecomeActive(_ type: ProtectionType)
    func applicationWillResignActive(_ application: UIApplication)
    func applicationDidBecomeActive(_ application: UIApplication)
    
    func enableScreenshotPrevention() -> Bool
    func disableScreenshotPrevention() -> Bool
    
    func isScreenRecording() -> Bool
    
    @discardableResult
    func setListener(for event: ListenerEvent, using handler: @escaping (ListenerPayload) -> Void) -> ListenerStatus
    
    @discardableResult
    func removeListener(for event: ListenerEvent) -> ListenerStatus
    
    @discardableResult
    func removeListeners() -> ListenerStatus
    
    @discardableResult
    func enableProtectionMode(_ mode: ProtectionMode) -> Bool
    
    @discardableResult
    func disableProtectionMode(_ mode: ProtectionMode) -> Bool
}

public final class ScreenProtectorKitManager: ScreenProtectorKitManaging {
    private let screenProtectorKit: ScreenProtectorKit?
    
    /// Creates a manager wrapping the provided ScreenProtectorKit.
    /// - Parameter screenProtectorKit: The underlying implementation to drive UI-related protections.
    /// - Note: The initializer configures screenshot prevention capability on the main thread.
    public init(screenProtectorKit: ScreenProtectorKit) {
        self.screenProtectorKit = screenProtectorKit
        onMain { self.screenProtectorKit?.configurePreventionScreenshot() }
    }
    
    private let syncQueue = DispatchQueue(label: "com.screenprotector.kit.manager.sync", attributes: .concurrent)
    
    private var _preventScreenshotState: ProtectionState = .idle
    private var _blurProtectionState: ProtectionState = .idle
    private var _imageProtectionState: ProtectionState = .idle
    private var _colorProtectionState: ProtectionState = .idle
    private var _imageProtectionName: String = ""
    private var _colorProtectionHex: String = ""
    
    private var preventScreenshotState: ProtectionState { syncQueue.sync { _preventScreenshotState } }
    private var blurProtectionState: ProtectionState { syncQueue.sync { _blurProtectionState } }
    private var imageProtectionState: ProtectionState { syncQueue.sync { _imageProtectionState } }
    private var colorProtectionState: ProtectionState { syncQueue.sync { _colorProtectionState } }
    private var imageProtectionName: String { syncQueue.sync { _imageProtectionName } }
    private var colorProtectionHex: String { syncQueue.sync { _colorProtectionHex } }
    
    // MARK: - State Snapshot (Get/Set)
    /// Returns a thread-safe snapshot of all internal states.
    /// - Returns: A `StateSnapshot` representing the current configuration.
    /// - Important: This method does not cause any UI side-effects.
    /// - Example:
    /// ```swift
    /// let snapshot = manager.getStateSnapshot()
    /// newManager.setStateSnapshot(snapshot)
    /// ```
    public func getStateSnapshot() -> StateSnapshot {
        return syncQueue.sync {
            StateSnapshot(
                preventScreenshotState: self._preventScreenshotState,
                blurProtectionState: self._blurProtectionState,
                imageProtectionState: self._imageProtectionState,
                colorProtectionState: self._colorProtectionState,
                imageProtectionName: self._imageProtectionName,
                colorProtectionHex: self._colorProtectionHex
            )
        }
    }
    
    /// Applies a snapshot to this manager without triggering UI side-effects.
    /// - Parameter snapshot: The state to apply.
    /// - Note: Call `configureState()` (or relevant lifecycle methods) afterward to enact changes.
    /// - Thread safety: Writes occur on a barrier queue.
    public func setStateSnapshot(_ snapshot: StateSnapshot) {
        syncQueue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            self._preventScreenshotState = snapshot.preventScreenshotState
            self._blurProtectionState = snapshot.blurProtectionState
            self._imageProtectionState = snapshot.imageProtectionState
            self._colorProtectionState = snapshot.colorProtectionState
            self._imageProtectionName = snapshot.imageProtectionName
            self._colorProtectionHex = snapshot.colorProtectionHex
        }
    }
    
    // MARK: - ScreenProtectorKitManaging
    /// Handles app transition to inactive state for the specified protection type.
    /// - Parameter type: The protection category to process.
    public func applicationWillResignActive(_ type: ProtectionType) {
        if type == .dataLeakage {
            // Protect Data Leakage - ON
            if colorProtectionState == .on {
                onMain { self.screenProtectorKit?.enabledColorScreen(hexColor: self.colorProtectionHex) }
            } else if imageProtectionState == .on {
                onMain { self.screenProtectorKit?.enabledImageScreen(named: self.imageProtectionName) }
            } else if blurProtectionState == .on {
                onMain { self.screenProtectorKit?.enabledBlurScreen() }
            }
        }
        
        if type == .screenshot {
            // Prevent Screenshot - OFF
            if preventScreenshotState == .off {
                onMain { self.screenProtectorKit?.disablePreventScreenshot() }
            }
        }
    }
    
    /// Handles app transition back to active state for the specified protection type.
    /// - Parameter type: The protection category to process.
    public func applicationDidBecomeActive(_ type: ProtectionType) {
        if type == .dataLeakage {
            // Protect Data Leakage - OFF
            if colorProtectionState == .on {
                onMain { self.screenProtectorKit?.disableColorScreen() }
            } else if imageProtectionState == .on {
                onMain { self.screenProtectorKit?.disableImageScreen() }
            } else if blurProtectionState == .on {
                onMain { self.screenProtectorKit?.disableBlurScreen() }
            }
        }
        
        if type == .screenshot {
            // Prevent Screenshot - ON
            if preventScreenshotState == .on {
                onMain { self.screenProtectorKit?.enabledPreventScreenshot() }
            }
        }
    }
    
    /// Convenience entry point to process all protection types on willResignActive.
    public func applicationWillResignActive(_ application: UIApplication) {
        applicationWillResignActive(.dataLeakage)
        applicationWillResignActive(.screenshot)
    }
    
    /// Convenience entry point to process all protection types on didBecomeActive.
    public func applicationDidBecomeActive(_ application: UIApplication) {
        applicationDidBecomeActive(.dataLeakage)
        applicationDidBecomeActive(.screenshot)
    }
    
    /// Disables all visual data leakage protection modes and updates the UI accordingly.
    /// - Returns: `true` on successful request dispatch.
    public func disableAllProtection() -> Bool {
        syncQueue.async(flags: .barrier) { self._colorProtectionState = .off }
        syncQueue.async(flags: .barrier) { self._imageProtectionState = .off }
        syncQueue.async(flags: .barrier) { self._blurProtectionState = .off }
        onMain { self.screenProtectorKit?.disableColorScreen() }
        onMain { self.screenProtectorKit?.disableImageScreen() }
        onMain { self.screenProtectorKit?.disableBlurScreen() }
        return true
    }
    
    /// Enables OS-level screenshot prevention and updates internal state.
    /// - Returns: `true` on successful request dispatch.
    /// - Note: Executes UI interaction on the main thread.
    public func enableScreenshotPrevention() -> Bool {
        syncQueue.async(flags: .barrier) { self._preventScreenshotState = .on }
        onMain { self.screenProtectorKit?.enabledPreventScreenshot() }
        return true
    }
    
    /// Disables OS-level screenshot prevention and updates internal state.
    /// - Returns: `true` on successful request dispatch.
    /// - Note: Executes UI interaction on the main thread.
    public func disableScreenshotPrevention() -> Bool {
        syncQueue.async(flags: .barrier) { self._preventScreenshotState = .off }
        onMain { self.screenProtectorKit?.disablePreventScreenshot() }
        return true
    }
    
    /// Indicates whether the screen is currently being recorded.
    /// - Returns: `true` if the system reports active screen recording; otherwise `false`.
    public func isScreenRecording() -> Bool {
        return screenProtectorKit?.screenIsRecording() ?? false
    }
    
    /// Registers a listener for the specified event.
    /// - Parameters:
    ///   - event: The event to observe.
    ///   - handler: Closure invoked with event payloads.
    /// - Returns: A `ListenerStatus` indicating the result.
    /// - Note: For `.screenRecording`, availability requires iOS 11 or later.
    @discardableResult
    public func setListener(for event: ListenerEvent, using handler: @escaping (ListenerPayload) -> Void) -> ListenerStatus {
        switch event {
        case .screenshot:
            onMain { self.screenProtectorKit?.removeScreenshotObserver() }
            onMain { self.screenProtectorKit?.screenshotObserver(using: { handler(.screenshot) }) }
            return .listened
        case .screenRecording:
            if #available(iOS 11.0, *) {
                onMain { self.screenProtectorKit?.removeScreenRecordObserver() }
                onMain { self.screenProtectorKit?.screenRecordObserver(using: { isRecording in
                    handler(.screenRecording(isRecording))
                }) }
                return .listened
            } else {
                return .unsupported
            }
        }
    }
    
    /// Removes the listener for the specified event.
    /// - Parameter event: The event whose listener should be removed.
    /// - Returns: A `ListenerStatus` indicating the result.
    @discardableResult
    public func removeListener(for event: ListenerEvent) -> ListenerStatus {
        switch event {
        case .screenshot:
            onMain { self.screenProtectorKit?.removeScreenshotObserver() }
            return .removed
        case .screenRecording:
            onMain { self.screenProtectorKit?.removeScreenRecordObserver() }
            return .removed
        }
    }
    
    /// Removes all listeners managed by this instance.
    /// - Returns: `.removed` after dispatching removal.
    @discardableResult
    public func removeListeners() -> ListenerStatus {
        onMain { self.screenProtectorKit?.removeAllObserver() }
        return .removed
    }
    
    /// Removes all listeners (alias of `removeListeners()`).
    /// - Returns: `.removed` after dispatching removal.
    @discardableResult
    public func removeAllListeners() -> ListenerStatus {
        onMain { self.screenProtectorKit?.removeAllObserver() }
        return .removed
    }
    
    /// Enables the specified visual protection mode.
    /// - Parameter mode: The protection mode to enable.
    /// - Returns: `true` on successful request dispatch.
    /// - Important: This updates internal state immediately; UI application may occur during lifecycle.
    @discardableResult
    public func enableProtectionMode(_ mode: ProtectionMode) -> Bool {
        switch mode {
        case .none:
            return disableAllProtection()
        case .blur:
            syncQueue.async(flags: .barrier) { self._blurProtectionState = .on }
            return true
        case .image(let name):
            syncQueue.async(flags: .barrier) { self._imageProtectionName = name }
            syncQueue.async(flags: .barrier) { self._imageProtectionState = .on }
            return true
        case .color(let hex):
            syncQueue.async(flags: .barrier) { self._colorProtectionHex = hex }
            syncQueue.async(flags: .barrier) { self._colorProtectionState = .on }
            return true
        }
    }
    
    /// Disables the specified visual protection mode and updates UI when applicable.
    /// - Parameter mode: The protection mode to disable.
    /// - Returns: `true` on successful request dispatch.
    @discardableResult
    public func disableProtectionMode(_ mode: ProtectionMode) -> Bool {
        switch mode {
        case .none:
            return disableAllProtection()
        case .blur:
            syncQueue.async(flags: .barrier) { self._blurProtectionState = .off }
            onMain { self.screenProtectorKit?.disableBlurScreen() }
            return true
        case .image:
            syncQueue.async(flags: .barrier) { self._imageProtectionState = .off }
            onMain { self.screenProtectorKit?.disableImageScreen() }
            return true
        case .color:
            syncQueue.async(flags: .barrier) { self._colorProtectionState = .off }
            onMain { self.screenProtectorKit?.disableColorScreen() }
            return true
        }
    }
}
