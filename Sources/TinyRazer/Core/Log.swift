import Foundation
import os

enum Log {
    static let transport = Logger(subsystem: "com.hyunseokbyun.tinyrazer", category: "transport")
    static let manager = Logger(subsystem: "com.hyunseokbyun.tinyrazer", category: "manager")
    static let ui = Logger(subsystem: "com.hyunseokbyun.tinyrazer", category: "ui")
}
