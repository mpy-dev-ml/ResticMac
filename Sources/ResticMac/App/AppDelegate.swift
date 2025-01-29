import SwiftUI
import Logging

class AppDelegate: NSObject, NSApplicationDelegate {
    private let logger = Logging.Logger(label: "com.resticmac.AppDelegate")
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        logger.info("ResticMac launched")
        
        // Verify Restic installation
        verifyResticInstallation()
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        logger.info("ResticMac will terminate")
    }
    
    private func verifyResticInstallation() {
        // We'll implement this later to check if Restic is installed
        // and show an error if it's not
    }
}