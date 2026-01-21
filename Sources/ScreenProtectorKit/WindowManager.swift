//
//  WindowManager.swift
//  ScreenProtectorKit
//
//  Created by INTENIQUETIC on 16/10/2568 BE.
//

#if canImport(UIKit)
import UIKit

public protocol WindowManaging {
    func getWindow() -> UIWindow?
}

public final class WindowManager: WindowManaging {
    public init() {}

    // MARK: - Public
    public func getWindow() -> UIWindow? {
        if Thread.isMainThread { return findKeyWindow() }

        var result: UIWindow?
        let semaphore = DispatchSemaphore(value: 0)

        DispatchQueue.main.async {
            result = self.findKeyWindow()
            semaphore.signal()
        }

        _ = semaphore.wait(timeout: .now() + 0.3)
        return result
    }

    // MARK: - Private
    private func findKeyWindow() -> UIWindow? {
        if #available(iOS 13.0, *) {
            // Try Scene-based window (modern)
            if let sceneWindow = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .flatMap({ $0.windows })
                .first(where: { $0.isKeyWindow }) { return sceneWindow }

            // Fallback → visible window
            if let anyWindow = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .flatMap({ $0.windows })
                .first { return anyWindow }

            // Fallback → AppDelegate window (legacy)
            if let legacyWindow = UIApplication.shared.delegate?.window as? UIWindow {
                return legacyWindow
            }
            return nil
        } else {
            let window = UIApplication.shared.delegate?.window as? UIWindow
            return window ?? UIApplication.shared.keyWindow
        }
    }
}
#endif