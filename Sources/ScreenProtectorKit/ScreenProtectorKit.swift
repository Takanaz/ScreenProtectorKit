//
//  ScreenProtectorKit.swift
//  Runner
//
//  Created by prongbang on 19/2/2565 BE.
//

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
    private var screenshotObserve: NSObjectProtocol? = nil
    private var screenRecordObserve: NSObjectProtocol? = nil
    
    public init(window: UIWindow?) {
        self.window = window
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
        
        if (!w.subviews.contains(screenPrevent)) {
            w.addSubview(screenPrevent)
            screenPrevent.centerYAnchor.constraint(equalTo: w.centerYAnchor).isActive = true
            screenPrevent.centerXAnchor.constraint(equalTo: w.centerXAnchor).isActive = true
            w.layer.superlayer?.addSublayer(screenPrevent.layer)
            if #available(iOS 17.0, *) {
                screenPrevent.layer.sublayers?.last?.addSublayer(w.layer)
            } else {
                screenPrevent.layer.sublayers?.first?.addSublayer(w.layer)
            }
        }
    }
    
    // How to used:
    //
    // override func applicationDidBecomeActive(_ application: UIApplication) {
    //     screenProtectorKit.enabledPreventScreenshot()
    // }
    public func enabledPreventScreenshot() {
        screenPrevent.isSecureTextEntry = true
    }
    
    // How to used:
    //
    // override func applicationWillResignActive(_ application: UIApplication) {
    //     screenProtectorKit.disablePreventScreenshot()
    // }
    public func disablePreventScreenshot() {
        screenPrevent.isSecureTextEntry = false
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
