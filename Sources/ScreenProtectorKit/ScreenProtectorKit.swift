//
//  ScreenProtectorKit.swift
//  Runner
//
//  Created by prongbang on 19/2/2565 BE.
//

#if canImport(UIKit)
import UIKit

//  How to used:
//
//  @UIApplicationMain
//  @objc class AppDelegate: FlutterAppDelegate {
//
//      private lazy var screenProtectorKit = { return ScreenProtectorKit(window: window) }()
//
//  }
public class ScreenProtectorKit {
    
    public var window: UIWindow? = nil
    private var screenImage: UIImageView? = nil
    private var screenBlur: UIView? = nil
    private var screenColor: UIView? = nil
    private var screenPrevent = UITextField()
    private var secureOverlayWindow: UIWindow? = nil
    private weak var previousKeyWindow: UIWindow? = nil
    private weak var windowSuperlayer: CALayer? = nil
    private var screenshotObserve: NSObjectProtocol? = nil
    private var screenRecordObserve: NSObjectProtocol? = nil
    private var isWindowLayerReparented = false
    private var isUpdatingPreventScreenshot = false
    private var lastReparentAt: TimeInterval = 0
    private let minReparentInterval: TimeInterval = 1.0
    private var lastRestoreAt: TimeInterval = 0
    private let minRestoreInterval: TimeInterval = 1.0
    private var safeAreaSentinel: SafeAreaSentinelView? = nil
    private var lastSafeAreaUpdateAt: TimeInterval = 0
    private let safeAreaCooldown: TimeInterval = 0.6
    private var pendingReparentState: ReparentState? = nil
    private var reparentWorkItem: DispatchWorkItem? = nil
    private let reparentDelay: TimeInterval = 0.2
    private let enableLayerReparenting: Bool = true
    private let restoreLayerOnDisable: Bool = true
    private let removeScreenPreventOnDisable: Bool = true
    private let useOverlayWindowForScreenshotProtection: Bool = false
    private var didBecomeActiveObserve: NSObjectProtocol? = nil
    private var willEnterForegroundObserve: NSObjectProtocol? = nil
    private var lastDidBecomeActiveAt: TimeInterval = 0
    private let reparentCooldownAfterActive: TimeInterval = 1.2
    
    private enum ReparentState {
        case on
        case off
    }
    
    public init(window: UIWindow?) {
        self.window = window
        self.lastDidBecomeActiveAt = ProcessInfo.processInfo.systemUptime
        observeDidBecomeActiveIfNeeded()
        observeWillEnterForegroundIfNeeded()
        installSafeAreaSentinelIfNeeded()
    }

    deinit {
        removeDidBecomeActiveObserver()
        removeWillEnterForegroundObserver()
    }

    private func observeDidBecomeActiveIfNeeded() {
        if didBecomeActiveObserve != nil { return }
        didBecomeActiveObserve = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: OperationQueue.main
        ) { [weak self] _ in
            self?.lastDidBecomeActiveAt = ProcessInfo.processInfo.systemUptime
        }
    }

    private func observeWillEnterForegroundIfNeeded() {
        if willEnterForegroundObserve != nil { return }
        willEnterForegroundObserve = NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: OperationQueue.main
        ) { [weak self] _ in
            self?.lastDidBecomeActiveAt = ProcessInfo.processInfo.systemUptime
        }
    }

    private func removeDidBecomeActiveObserver() {
        if let obs = didBecomeActiveObserve {
            NotificationCenter.default.removeObserver(obs)
            didBecomeActiveObserve = nil
        }
    }

    private func removeWillEnterForegroundObserver() {
        if let obs = willEnterForegroundObserve {
            NotificationCenter.default.removeObserver(obs)
            willEnterForegroundObserve = nil
        }
    }
    
    //  How to used:
    //
    //  override func application(
    //      _ application: UIApplication,
    //      didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    //  ) -> Bool {
    //
    //      screenProtectorKit.configurePreventionScreenshot()
    //
    //      return true
    //  }
    public func configurePreventionScreenshot() {
        guard let w = window else { return }
        installSafeAreaSentinelIfNeeded()

        if (!w.subviews.contains(screenPrevent)) {
            screenPrevent.isUserInteractionEnabled = false
            screenPrevent.backgroundColor = .clear
            screenPrevent.textColor = .clear
            screenPrevent.frame = w.bounds
            screenPrevent.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            w.addSubview(screenPrevent)
        }
    }
    
    // How to used:
    //
    // override func applicationDidBecomeActive(_ application: UIApplication) {
    //     screenProtectorKit.enabledPreventScreenshot()
    // }
    public func enabledPreventScreenshot() {
        guard window != nil else { return }
        if isUpdatingPreventScreenshot { return }
        isUpdatingPreventScreenshot = true
        defer { isUpdatingPreventScreenshot = false }
        if useOverlayWindowForScreenshotProtection {
            showSecureOverlay()
            return
        }
        configurePreventionScreenshot()

        screenPrevent.isSecureTextEntry = true

        if !enableLayerReparenting {
            return
        }
        if !isWindowLayerReparented {
            scheduleReparent(.on)
        }
    }
    
    // How to used:
    //
    // override func applicationWillResignActive(_ application: UIApplication) {
    //     screenProtectorKit.disablePreventScreenshot()
    // }
    public func disablePreventScreenshot() {
        guard window != nil else { return }
        if useOverlayWindowForScreenshotProtection {
            hideSecureOverlay()
            return
        }
        screenPrevent.isSecureTextEntry = false
        if !enableLayerReparenting {
            return
        }
        if restoreLayerOnDisable && isWindowLayerReparented {
            scheduleReparent(.off)
        }
        if removeScreenPreventOnDisable, let w = window {
            if screenPrevent.superview === w {
                screenPrevent.removeFromSuperview()
            }
        }
    }

    private func showSecureOverlay() {
        guard let w = window else { return }
        let overlay = ensureSecureOverlayWindow(for: w)
        if previousKeyWindow == nil {
            previousKeyWindow = UIApplication.shared.windows.first { $0.isKeyWindow }
        }
        overlay.isHidden = false
        overlay.makeKeyAndVisible()
    }

    private func hideSecureOverlay() {
        secureOverlayWindow?.isHidden = true
        if let previous = previousKeyWindow {
            previous.makeKeyAndVisible()
            previousKeyWindow = nil
        }
    }

    private func ensureSecureOverlayWindow(for w: UIWindow) -> UIWindow {
        if let existing = secureOverlayWindow, existing.windowScene === w.windowScene {
            if let rootView = existing.rootViewController?.view {
                if rootView.bounds != w.bounds {
                    rootView.frame = w.bounds
                }
            }
            return existing
        }

        let overlayWindow: UIWindow
        if #available(iOS 13.0, *), let scene = w.windowScene {
            overlayWindow = UIWindow(windowScene: scene)
        } else {
            overlayWindow = UIWindow(frame: w.bounds)
        }

        let rootVC = UIViewController()
        rootVC.view.backgroundColor = .clear
        rootVC.view.isUserInteractionEnabled = false
        rootVC.view.frame = w.bounds
        rootVC.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]

        screenPrevent.removeFromSuperview()
        screenPrevent.isUserInteractionEnabled = false
        screenPrevent.backgroundColor = .clear
        screenPrevent.textColor = .clear
        screenPrevent.isSecureTextEntry = true
        screenPrevent.frame = rootVC.view.bounds
        screenPrevent.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        rootVC.view.addSubview(screenPrevent)

        overlayWindow.rootViewController = rootVC
        overlayWindow.windowLevel = .alert + 1
        overlayWindow.isHidden = true
        overlayWindow.backgroundColor = .clear
        overlayWindow.isUserInteractionEnabled = false

        secureOverlayWindow = overlayWindow
        return overlayWindow
    }

    private func scheduleReparent(_ state: ReparentState) {
        pendingReparentState = state
        reparentWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard let w = self.window else { return }
            guard let pending = self.pendingReparentState else { return }
            self.pendingReparentState = nil
            switch pending {
            case .on:
                guard self.canReparentWindowLayer(w) else { return }
                guard self.canReparentNow() else {
                    self.scheduleReparent(.on)
                    return
                }
                self.attachSecureLayerIfNeeded(w)
            case .off:
                guard self.canRestoreWindowLayer(w) else {
                    DispatchQueue.main.asyncAfter(deadline: .now() + self.reparentDelay) { [weak self] in
                        self?.scheduleReparent(.off)
                    }
                    return
                }
                guard self.canRestoreNow() else {
                    DispatchQueue.main.asyncAfter(deadline: .now() + self.reparentDelay) { [weak self] in
                        self?.scheduleReparent(.off)
                    }
                    return
                }
                self.restoreWindowLayerIfNeeded(w)
            }
        }
        reparentWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + reparentDelay, execute: workItem)
    }

    private func attachSecureLayerIfNeeded(_ w: UIWindow) {
        installSafeAreaSentinelIfNeeded()
        if windowSuperlayer == nil {
            windowSuperlayer = w.layer.superlayer
        }

        guard let superlayer = windowSuperlayer else { return }
        // window.layer.superlayer が無い場合は不安定なので延期
        if w.layer.superlayer == nil {
            scheduleReparent(.on)
            return
        }

        if screenPrevent.layer.superlayer !== superlayer {
            superlayer.addSublayer(screenPrevent.layer)
        }

        let secureLayer: CALayer? = {
            if #available(iOS 17.0, *) {
                return screenPrevent.layer.sublayers?.last
            }
            return screenPrevent.layer.sublayers?.first
        }()

        guard let secureLayer = secureLayer else {
            // secure layer がまだ生成されていない
            scheduleReparent(.on)
            return
        }

        if w.layer.superlayer !== secureLayer {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            w.layer.removeFromSuperlayer()
            secureLayer.addSublayer(w.layer)
            CATransaction.commit()
            isWindowLayerReparented = true
            lastReparentAt = ProcessInfo.processInfo.systemUptime
        }
    }
    
    private func restoreWindowLayerIfNeeded(_ w: UIWindow) {
        guard isWindowLayerReparented else { return }
        // safeArea 更新直後は触らない
        if lastSafeAreaUpdateAt > 0 {
            let now = ProcessInfo.processInfo.systemUptime
            if now - lastSafeAreaUpdateAt < safeAreaCooldown {
                scheduleReparent(.off)
                return
            }
        }
        guard let superlayer = resolveWindowSuperlayer(w) else {
            // superlayer が取れない場合は復元できないため再試行
            scheduleReparent(.off)
            return
        }
        // layer が不安定なら延期
        guard w.layer.superlayer != nil else {
            scheduleReparent(.off)
            return
        }
        guard screenPrevent.layer.superlayer != nil else {
            scheduleReparent(.off)
            return
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if w.layer.superlayer !== superlayer {
            w.layer.removeFromSuperlayer()
            superlayer.addSublayer(w.layer)
        }

        if screenPrevent.layer.superlayer !== w.layer {
            screenPrevent.layer.removeFromSuperlayer()
            w.layer.addSublayer(screenPrevent.layer)
        }
        CATransaction.commit()
        isWindowLayerReparented = false
        lastRestoreAt = ProcessInfo.processInfo.systemUptime
    }

    private func canReparentWindowLayer(_ w: UIWindow) -> Bool {
        let now = ProcessInfo.processInfo.systemUptime
        if lastDidBecomeActiveAt > 0,
           now - lastDidBecomeActiveAt < reparentCooldownAfterActive {
            return false
        }
        if lastSafeAreaUpdateAt > 0,
           now - lastSafeAreaUpdateAt < safeAreaCooldown {
            return false
        }
        if #available(iOS 13.0, *) {
            if w.windowScene?.activationState != .foregroundActive {
                return false
            }
        }
        if w.isHidden || w.alpha <= 0.0 {
            return false
        }
        if w.bounds.isEmpty || w.bounds == .zero {
            return false
        }
        let screenBounds = (w.windowScene?.screen.bounds ?? UIScreen.main.bounds).integral
        if w.bounds.integral != screenBounds {
            return false
        }
        return true
    }

    private func canReparentNow() -> Bool {
        let now = ProcessInfo.processInfo.systemUptime
        if lastReparentAt > 0, now - lastReparentAt < minReparentInterval {
            return false
        }
        return true
    }

    private func canRestoreNow() -> Bool {
        let now = ProcessInfo.processInfo.systemUptime
        if lastRestoreAt > 0, now - lastRestoreAt < minRestoreInterval {
            return false
        }
        if lastSafeAreaUpdateAt > 0, now - lastSafeAreaUpdateAt < safeAreaCooldown {
            return false
        }
        return true
    }

    private func installSafeAreaSentinelIfNeeded() {
        guard let w = window else { return }
        if safeAreaSentinel != nil { return }
        let sentinel = SafeAreaSentinelView(frame: .zero)
        sentinel.isUserInteractionEnabled = false
        sentinel.isHidden = true
        sentinel.onSafeAreaChange = { [weak self] in
            self?.lastSafeAreaUpdateAt = ProcessInfo.processInfo.systemUptime
        }
        w.addSubview(sentinel)
        safeAreaSentinel = sentinel
    }

    private func resolveWindowSuperlayer(_ w: UIWindow) -> CALayer? {
        if let existing = windowSuperlayer {
            return existing
        }
        if let fromPrevent = screenPrevent.layer.superlayer {
            windowSuperlayer = fromPrevent
            return fromPrevent
        }
        // w.layer.superlayer は secureLayer の可能性がある
        if let secureLayer = w.layer.superlayer,
           let preventLayer = secureLayer.superlayer,
           let superlayer = preventLayer.superlayer {
            windowSuperlayer = superlayer
            return superlayer
        }
        return nil
    }

    private func canRestoreWindowLayer(_ w: UIWindow) -> Bool {
        if #available(iOS 13.0, *) {
            if w.windowScene?.activationState != .foregroundActive {
                return false
            }
        }
        if w.isHidden || w.alpha <= 0.0 {
            return false
        }
        if w.bounds.isEmpty || w.bounds == .zero {
            return false
        }
        return true
    }
    
    // How to used:
    //
    // override func applicationWillResignActive(_ application: UIApplication) {
    //     screenProtectorKit.enabledBlurScreen()
    // }
    public func enabledBlurScreen(style: UIBlurEffect.Style = UIBlurEffect.Style.light) {
        guard let w = window else { return }

        if self.screenBlur == nil {
            let blurEffect = UIBlurEffect(style: style)
            let blurView = UIVisualEffectView(effect: blurEffect)
            blurView.frame = w.bounds
            blurView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            blurView.isUserInteractionEnabled = false
            screenBlur = blurView
            w.addSubview(blurView)
        }

        screenBlur?.isHidden = false
        screenBlur?.alpha = 1.0
    }
    
    // How to used:
    //
    // override func applicationDidBecomeActive(_ application: UIApplication) {
    //     screenProtectorKit.disableBlurScreen()
    // }
    public func disableBlurScreen() {
        screenBlur?.alpha = 0.0
        screenBlur?.isHidden = true
    }
    
    // How to used:
    //
    // override func applicationWillResignActive(_ application: UIApplication) {
    //     screenProtectorKit.enabledColorScreen(hexColor: "#ffffff")
    // }
    public func enabledColorScreen(hexColor: String) {
        guard let w = window else { return }

        if screenColor == nil {
            let view = UIView(frame: w.bounds)
            view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            view.backgroundColor = UIColor(hexString: hexColor)
            screenColor = view
            w.addSubview(view)
        }

        screenColor?.isHidden = false
        screenColor?.alpha = 1.0
    }
    
    // How to used:
    //
    // override func applicationDidBecomeActive(_ application: UIApplication) {
    //     screenProtectorKit.disableColorScreen()
    // }
    public func disableColorScreen() {
        screenColor?.isHidden = true
        screenColor?.alpha = 0.0
    }
    
    // How to used:
    //
    // override func applicationWillResignActive(_ application: UIApplication) {
    //     screenProtectorKit.enabledImageScreen(named: "LaunchImage")
    // }
    public func enabledImageScreen(named: String) {
        guard let w = window else { return }

        if screenImage == nil {
            let imageView = UIImageView(frame: w.bounds)
            imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            imageView.image = UIImage(named: named)
            imageView.isUserInteractionEnabled = false
            imageView.contentMode = .scaleAspectFill
            imageView.clipsToBounds = true
            screenImage = imageView
            w.addSubview(imageView)
        }

        screenImage?.isHidden = false
        screenImage?.alpha = 1.0
    }
    
    // How to used:
    //
    // override func applicationDidBecomeActive(_ application: UIApplication) {
    //     screenProtectorKit.disableImageScreen()
    // }
    public func disableImageScreen() {
        screenImage?.isHidden = true
        screenImage?.alpha = 0.0
    }
    
    // How to used:
    //
    // screenProtectorKit.removeObserver(observer: screenRecordObserve)
    public func removeObserver(observer: NSObjectProtocol?) {
        guard let obs = observer else {return}
        NotificationCenter.default.removeObserver(obs)
    }
    
    // How to used:
    //
    // screenProtectorKit.removeScreenshotObserver()
    public func removeScreenshotObserver() {
        if screenshotObserve != nil {
            self.removeObserver(observer: screenshotObserve)
            self.screenshotObserve = nil
        }
    }
    
    // How to used:
    //
    // screenProtectorKit.removeScreenRecordObserver()
    public func removeScreenRecordObserver() {
        if screenRecordObserve != nil {
            self.removeObserver(observer: screenRecordObserve)
            self.screenRecordObserve = nil
        }
    }
    
    // How to used:
    //
    // screenProtectorKit.removeAllObserver()
    public func removeAllObserver() {
        self.removeScreenshotObserver()
        self.removeScreenRecordObserver()
    }
    
    // How to used:
    //
    // screenProtectorKit.screenshotObserver {
    //      // Callback on Screenshot
    // }
    public func screenshotObserver(using onScreenshot: @escaping () -> Void) {
        screenshotObserve = NotificationCenter.default.addObserver(
            forName: UIApplication.userDidTakeScreenshotNotification,
            object: nil,
            queue: OperationQueue.main
        ) { notification in
            onScreenshot()
        }
    }
    
    // How to used:
    //
    // if #available(iOS 11.0, *) {
    //     screenProtectorKit.screenRecordObserver { isCaptured in
    //         // Callback on Screen Record
    //     }
    // }
    @available(iOS 11.0, *)
    public func screenRecordObserver(using onScreenRecord: @escaping (Bool) -> Void) {
        screenRecordObserve =
        NotificationCenter.default.addObserver(
            forName: UIScreen.capturedDidChangeNotification,
            object: nil,
            queue: OperationQueue.main
        ) { notification in
            let isCaptured = UIScreen.main.isCaptured
            onScreenRecord(isCaptured)
        }
    }
    
    // How to used:
    //
    // if #available(iOS 11.0, *) {
    //     screenProtectorKit.screenIsRecording()
    // }
    @available(iOS 11.0, *)
    public func screenIsRecording() -> Bool {
        return UIScreen.main.isCaptured
    }
}

private final class SafeAreaSentinelView: UIView {
    var onSafeAreaChange: (() -> Void)?
    override func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()
        onSafeAreaChange?()
    }
}
#endif