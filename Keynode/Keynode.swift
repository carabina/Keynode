//
//  Keynode.swift
//  Keynode
//
//  Created by Kyohei Ito on 2014/11/10.
//  Copyright (c) 2014年 kyohei_ito. All rights reserved.
//

import UIKit

@objc public protocol ControllerDelegate {
    /**
     * return false if need be not gesture.
     */
    optional func controller(controller: Controller, shouldHandlePanningKeyboardAtResponder responder: UIResponder) -> Bool
}

class Keyboard {
    weak var view: UIView?
    struct Singleton {
        static let instance = Keyboard()
    }
    
    class func sharedKeyboard() -> UIView? {
        return Singleton.instance.view
    }
    
    class func setKeyboard(newValue: UIView?) {
        if let view = newValue {
            if Singleton.instance.view != view {
                Singleton.instance.view = view
            }
        }
    }
}

class Responder {
    weak var responder: UIResponder?
    var blankAccessoryView = UIView()
    var inputAccessoryView: UIView? {
        set {
            if let textView = responder as? UITextView {
                textView.inputAccessoryView = newValue
            } else if let textField = responder as? UITextField {
                textField.inputAccessoryView = newValue
            }
        }
        get {
            return responder?.inputAccessoryView
        }
    }
    var keyboard: UIView? {
        Keyboard.setKeyboard(inputAccessoryView?.superview)
        
        return Keyboard.sharedKeyboard()
    }
    init(_ responder: UIResponder) {
        self.responder = responder
        
        if inputAccessoryView == nil {
            inputAccessoryView = blankAccessoryView
        } else {
            Keyboard.setKeyboard(inputAccessoryView?.superview)
        }
    }
    deinit {
        if inputAccessoryView == blankAccessoryView {
            inputAccessoryView = nil
        }
        keyboard?.hidden = false
    }
}

class Info {
    let AnimationDuration: NSTimeInterval = 0.25
    let AnimationCurve: UInt = 7
    
    var userInfo: [NSObject : AnyObject]?
    var duration: NSTimeInterval {
        if let duration = userInfo?[UIKeyboardAnimationDurationUserInfoKey] as? NSTimeInterval {
            return duration
        }
        return AnimationDuration
    }
    
    var curve: UIViewAnimationOptions {
        if let curve = userInfo?[UIKeyboardAnimationCurveUserInfoKey] as? UInt {
            return animationOptionsForAnimationCurve(curve)
        }
        return animationOptionsForAnimationCurve(AnimationCurve)
    }
    
    var frame: CGRect? {
        let frame = userInfo?[UIKeyboardFrameEndUserInfoKey]?.CGRectValue()
        if let rect = frame {
            if rect.origin.x.isInfinite || rect.origin.y.isInfinite {
                return nil
            }
        }
        return frame
    }
    
    init(_ userInfo: [NSObject : AnyObject]? = nil) {
        self.userInfo = userInfo
    }
    
    func animationOptionsForAnimationCurve(curve: UInt) -> UIViewAnimationOptions {
        return UIViewAnimationOptions(curve << 16)
    }
}

public class Controller: NSObject {
    struct Singleton {
        static var instance: UITextField? {
            didSet {
                if let textField = instance {
                    
                    textField.inputAccessoryView = UIView()
                    textField.inputView = UIView()
                    
                    if let window = UIApplication.sharedApplication().windows.first as? UIWindow {
                        window.addSubview(textField)
                    }
                }
            }
        }
    }
    
    var workingInstance: Controller?
    var workingTextField: UITextField? {
        set {
            Singleton.instance = newValue
        }
        get {
            return Singleton.instance
        }
    }
    
    override public class func initialize() {
        super.initialize()
        
        if self.isEqual(Controller.self) {
            let controller = Controller()
            controller.workingInstance = controller
            
            controller.workingTextField = UITextField()
            
            dispatch_async(dispatch_get_main_queue()) {
                controller.workingTextField?.becomeFirstResponder()
                return
            }
        }
    }
    
    public var willAnimationHandler: ((show: Bool, rect: CGRect) -> Void)?
    public var animationsHandler: ((show: Bool, rect: CGRect) -> Void)?
    public var completionHandler: ((show: Bool, responder: UIResponder?, keyboard: UIView?) -> Void)?
    
    var firstResponder: Responder?
    weak var targetView: UIView?
    lazy var panGesture: UIPanGestureRecognizer = UIPanGestureRecognizer(target: self, action: "panGestureAction:")
    
    public weak var delegate: ControllerDelegate?
    public var gesturePanning: Bool = true
    public var autoScrollInset: Bool = true
    public var defaultInsetBottom: CGFloat = 0 {
        didSet {
            if let scrollView = targetView as? UIScrollView {
                scrollView.contentInset.bottom = defaultInsetBottom
            }
        }
    }
    var gestureHandle: Bool = true
    
    var _gestureOffset: CGFloat?
    public var gestureOffset: CGFloat {
        set {
            _gestureOffset = newValue
        }
        get {
            if let offset = _gestureOffset {
                return offset
            }
            return defaultInsetBottom
        }
    }
    public init(view: UIView? = nil) {
        self.targetView = view
        super.init()
        
        let center = NSNotificationCenter.defaultCenter()
        
        if view != nil {
            panGesture.delegate = self
            
            center.addObserver(self, selector: "keyboardWillShow:", name: UIKeyboardWillShowNotification, object: nil)
            center.addObserver(self, selector: "keyboardWillHide:", name: UIKeyboardWillHideNotification, object: nil)
            
            center.addObserver(self, selector: "textDidBeginEditing:", name: UITextFieldTextDidBeginEditingNotification, object: nil)
            center.addObserver(self, selector: "textDidBeginEditing:", name: UITextViewTextDidBeginEditingNotification, object: nil)
        }
        
        center.addObserver(self, selector: "keyboardDidShow:", name: UIKeyboardDidShowNotification, object: nil)
        center.addObserver(self, selector: "keyboardDidHide:", name: UIKeyboardDidHideNotification, object: nil)
    }
    
    deinit {
        workingTextField = nil
        NSNotificationCenter.defaultCenter().removeObserver(self)
    }
    
    func willShowAnimation(show: Bool, rect: CGRect, duration: NSTimeInterval, options: UIViewAnimationOptions) {
        var keyboardRect = convertKeyboardRect(rect)
        willAnimationHandler?(show: show, rect: keyboardRect)
        
        func animations() {
            offsetInsetBottom(keyboardRect.origin.y)
            animationsHandler?(show: show, rect: keyboardRect)
        }
        func completion(finished: Bool) {
            completionHandler?(show: show, responder: firstResponder?.responder, keyboard: firstResponder?.keyboard)
        }
        UIView.animateWithDuration(duration, delay: 0, options: options, animations: animations, completion: completion)
    }
    
    func offsetInsetBottom(originY: CGFloat) {
        if autoScrollInset == false {
            return
        }
        
        if let scrollView = targetView as? UIScrollView {
            let height = max(scrollView.bounds.height - originY, 0)
            scrollView.contentInset.bottom = height + defaultInsetBottom
        }
    }
    
    func convertKeyboardRect(var rect: CGRect) -> CGRect {
        if let window = targetView?.window {
            rect = window.convertRect(rect, toView: targetView)
            
            if let scrollView = targetView as? UIScrollView {
                rect.origin.y -= scrollView.contentOffset.y
            }
        }
        return rect
    }
    
    func changeLocation(location: CGPoint, keyboard: UIView, window: UIWindow) {
        let keyboardHeight = keyboard.bounds.size.height
        let windowHeight = window.bounds.size.height
        let thresholdHeight = windowHeight - keyboardHeight
        
        var keyboardRect = keyboard.frame
        keyboardRect.origin.y = min(location.y + gestureOffset, windowHeight)
        keyboardRect.origin.y = max(keyboardRect.origin.y, thresholdHeight)
        
        if keyboardRect.origin.y != keyboard.frame.origin.y {
            let show = keyboardRect.origin.y < keyboard.frame.origin.y
            animationsHandler?(show: show, rect: keyboardRect)
            keyboard.frame = keyboardRect
        }
    }
    
    func changeLocationForAnimation(location: CGPoint, velocity: CGPoint, keyboard: UIView, window: UIWindow) {
        let keyboardHeight = keyboard.bounds.size.height
        let windowHeight = window.bounds.size.height
        let thresholdHeight = windowHeight - keyboardHeight
        let show = (location.y + gestureOffset < thresholdHeight || velocity.y < 0)
        
        var keyboardRect = keyboard.frame
        keyboardRect.origin.y = show ? thresholdHeight : windowHeight
        
        func animations() {
            offsetInsetBottom(keyboardRect.origin.y)
            animationsHandler?(show: show, rect: keyboardRect)
            keyboard.frame = keyboardRect
            
            if show == false {
                targetView?.removeGestureRecognizer(panGesture)
            }
        }
        func completion(finished: Bool) {
            if show == false {
                keyboard.hidden = true
                firstResponder?.responder?.resignFirstResponder()
            }
        }
        
        let info = Info()
        let options = info.curve | .BeginFromCurrentState
        UIView.animateWithDuration(info.duration, delay: 0, options: options, animations: animations, completion: completion)
    }
}

// MARK: - Action Methods
extension Controller {
    func panGestureAction(gesture: UIPanGestureRecognizer) {
        if let keyboard = firstResponder?.keyboard {
            if let window = keyboard.window {
                if gesture.state == .Changed {
                    let location = gesture.locationInView(window)
                    
                    changeLocation(location, keyboard: keyboard, window: window)
                } else if gesture.state == .Ended || gesture.state == .Cancelled {
                    let location = gesture.locationInView(window)
                    let velocity = gesture.velocityInView(keyboard)
                    
                    changeLocationForAnimation(location, velocity: velocity, keyboard: keyboard, window: window)
                }
            }
        }
    }
}

// MARK: - UIGestureRecognizerDelegate Methods
extension Controller: UIGestureRecognizerDelegate {
    public func gestureRecognizer(gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWithGestureRecognizer otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return gestureRecognizer == panGesture || otherGestureRecognizer == panGesture
    }
}

// MARK: - NSNotificationCenter Methods
extension Controller {
    func checkWork(responder: UIResponder?) -> Bool {
        if let responder = responder {
            if responder == firstResponder?.responder {
                return true
            }
        }
        return false
    }
    
    func textDidBeginEditing(notification: NSNotification) {
        if let responder = notification.object as? UIResponder {
            firstResponder = Responder(responder)
            if checkWork(workingTextField) {
                return
            }
            
            if delegate?.controller?(self, shouldHandlePanningKeyboardAtResponder: responder) == false {
                gestureHandle = false
            } else {
                gestureHandle = true
            }
        }
    }
    
    func keyboardWillShow(notification: NSNotification) {
        if checkWork(workingTextField) {
            return
        }
        
        let info = Info(notification.userInfo)
        
        if let rect = info.frame {
            willShowAnimation(true, rect: rect, duration: info.duration, options: info.curve | .BeginFromCurrentState)
        }
    }
    
    func keyboardDidShow(notification: NSNotification) {
        if checkWork(workingTextField) {
            return
        }
        
        if let textField = workingTextField {
            Responder(textField)
            textField.resignFirstResponder()
            textField.removeFromSuperview()
            return
        }
        
        if let responder = firstResponder {
            if gestureHandle == true && gesturePanning == true {
                targetView?.addGestureRecognizer(panGesture)
            }
        }
    }
    
    func keyboardWillHide(notification: NSNotification) {
        if checkWork(workingTextField) {
            return
        }
        
        targetView?.removeGestureRecognizer(panGesture)
        
        let info = Info(notification.userInfo)
        
        if let rect = info.frame {
            willShowAnimation(false, rect: rect, duration: info.duration, options: info.curve | .BeginFromCurrentState)
        }
    }
    
    func keyboardDidHide(notification: NSNotification) {
        workingInstance = nil
    }
}
