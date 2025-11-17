//
//  ScreenProtectorKitManager.swift
//  ScreenProtectorKit
//
//  Created by INTENIQUETIC on 16/10/2568 BE.
//

import UIKit

public func onMain(_ work: @escaping () -> Void) {
    if Thread.isMainThread { work() } else { DispatchQueue.main.async(execute: work) }
}

public enum ProtectionState {
    case idle
    case on
    case off
}

public enum ListenerStatus: String, Equatable {
    case listened
    case removed
    case unsupported
}

public enum ListenerEvent: Equatable {
    case screenshot
    case screenRecording
}

public enum ListenerPayload: Equatable {
    case screenshot
    case screenRecording(Bool)
}

// Protection modes to prevent data leakage
public enum ProtectionMode: Equatable {
    case none
    case blur
    case image(name: String)
    case color(hex: String)
}

public protocol ScreenProtectorKitManaging: AnyObject {
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
    
    // MARK: - ScreenProtectorKitManaging
    public func applicationWillResignActive(_ application: UIApplication) {
        // Protect Data Leakage - ON
        if colorProtectionState == .on {
            onMain { self.screenProtectorKit?.enabledColorScreen(hexColor: self.colorProtectionHex) }
        } else if imageProtectionState == .on {
            onMain { self.screenProtectorKit?.enabledImageScreen(named: self.imageProtectionName) }
        } else if blurProtectionState == .on {
            onMain { self.screenProtectorKit?.enabledBlurScreen() }
        }
        
        // Prevent Screenshot - OFF
        if preventScreenshotState == .off {
            onMain { self.screenProtectorKit?.disablePreventScreenshot() }
        }
    }
    
    public func applicationDidBecomeActive(_ application: UIApplication) {
        // Protect Data Leakage - OFF
        if colorProtectionState == .on {
            onMain { self.screenProtectorKit?.disableColorScreen() }
        } else if imageProtectionState == .on {
            onMain { self.screenProtectorKit?.disableImageScreen() }
        } else if blurProtectionState == .on {
            onMain { self.screenProtectorKit?.disableBlurScreen() }
        }
        
        // Prevent Screenshot - ON
        if preventScreenshotState == .on {
            onMain { self.screenProtectorKit?.enabledPreventScreenshot() }
        }
    }
    
    public func disableAllProtection() -> Bool {
        syncQueue.async(flags: .barrier) { self._colorProtectionState = .off }
        syncQueue.async(flags: .barrier) { self._imageProtectionState = .off }
        syncQueue.async(flags: .barrier) { self._blurProtectionState = .off }
        onMain { self.screenProtectorKit?.disableColorScreen() }
        onMain { self.screenProtectorKit?.disableImageScreen() }
        onMain { self.screenProtectorKit?.disableBlurScreen() }
        return true
    }
    
    public func enableScreenshotPrevention() -> Bool {
        syncQueue.async(flags: .barrier) { self._preventScreenshotState = .on }
        onMain { self.screenProtectorKit?.enabledPreventScreenshot() }
        return true
    }
    
    public func disableScreenshotPrevention() -> Bool {
        syncQueue.async(flags: .barrier) { self._preventScreenshotState = .off }
        onMain { self.screenProtectorKit?.disablePreventScreenshot() }
        return true
    }
    
    public func isScreenRecording() -> Bool {
        return screenProtectorKit?.screenIsRecording() ?? false
    }
    
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
    
    @discardableResult
    public func removeListeners() -> ListenerStatus {
        onMain { self.screenProtectorKit?.removeAllObserver() }
        return .removed
    }
    
    @discardableResult
    public func removeAllListeners() -> ListenerStatus {
        onMain { self.screenProtectorKit?.removeAllObserver() }
        return .removed
    }
    
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
