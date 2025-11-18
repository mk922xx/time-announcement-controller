import SwiftUI
import Foundation
import AppKit
import CoreAudio

class AppState: ObservableObject {
    @Published var volume: Double = 30.0
    @Published var outputDevice: String = "デフォルト"
    @Published var availableOutputDevices: [AudioDevice] = []
    @Published var commandPath: String = "/usr/bin/open"
    @Published var commandArgs: String = "/Applications/Automator/AnnounceTime.app"
    @Published var launchAgentEnabled: Bool = false
    @Published var isRunning: Bool = false
    @Published var logEntries: [LogEntry] = []
    
    struct AudioDevice: Identifiable, Hashable {
        let id: String
        let name: String
        let uid: String
        let deviceID: AudioDeviceID?
        
        init(id: String, name: String, uid: String, deviceID: AudioDeviceID? = nil) {
            self.id = id
            self.name = name
            self.uid = uid
            self.deviceID = deviceID
        }
    }
    
    private var originalOutputDeviceID: AudioDeviceID?
    
    private let settingsKey = "AnnounceHelperSettings"
    private let launchAgentPath = "com.moto.announcetime"
    private let launchAgentFile = "com.moto.announcetime.plist"
    
    struct LogEntry: Identifiable {
        let id = UUID()
        let timestamp: String
        let message: String
        let error: String?
        var hasError: Bool { error != nil }
    }
    
    init() {
        loadSettings()
        loadAvailableOutputDevices()
        checkLaunchAgentStatus()
        refreshLog()
    }
    
    // MARK: - 音声出力デバイス取得
    func loadAvailableOutputDevices() {
        var devices: [AudioDevice] = []
        
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize
        )
        
        guard status == noErr else {
            // エラー時はデフォルトのみ
            devices.append(AudioDevice(id: "default", name: "デフォルト", uid: "default", deviceID: nil))
            availableOutputDevices = devices
            return
        }
        
        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)
        
        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &deviceIDs
        )
        
        guard status == noErr else {
            devices.append(AudioDevice(id: "default", name: "デフォルト", uid: "default", deviceID: nil))
            availableOutputDevices = devices
            return
        }
        
        // デフォルトを追加
        devices.append(AudioDevice(id: "default", name: "デフォルト", uid: "default", deviceID: nil))
        
        // 各デバイスの情報を取得
        for deviceID in deviceIDs {
            // 出力デバイスかどうか確認
            var propertyAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyStreams,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: kAudioObjectPropertyElementMain
            )
            
            var hasOutput: UInt32 = 0
            var dataSize = UInt32(MemoryLayout<UInt32>.size)
            var status = AudioObjectGetPropertyData(
                deviceID,
                &propertyAddress,
                0,
                nil,
                &dataSize,
                &hasOutput
            )
            
            guard status == noErr, hasOutput > 0 else {
                continue
            }
            
            // デバイス名を取得
            propertyAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceNameCFString,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            
            var deviceName: CFString?
            dataSize = UInt32(MemoryLayout<CFString?>.size)
            status = AudioObjectGetPropertyData(
                deviceID,
                &propertyAddress,
                0,
                nil,
                &dataSize,
                &deviceName
            )
            
            if let name = deviceName as String? {
                // Macminiのスピーカーの場合、表記を変更
                let displayName: String
                if name.contains("Macmini") || name.contains("Built-in") {
                    displayName = "Macminiのスピーカー"
                } else if name.contains("HDMI") || name.contains("Display") {
                    // HDMIモニタの場合、モニタ名を取得
                    displayName = getDisplayName(for: deviceID) ?? name
                } else {
                    displayName = name
                }
                
                let uid = "\(deviceID)"
                devices.append(AudioDevice(id: uid, name: displayName, uid: uid, deviceID: deviceID))
            }
        }
        
        availableOutputDevices = devices
        
        // 現在のデバイスがリストにない場合はデフォルトに設定
        if !devices.contains(where: { $0.name == outputDevice }) {
            outputDevice = "デフォルト"
        }
    }
    
    // MARK: - 出力デバイス制御
    func getCurrentOutputDeviceID() -> AudioDeviceID? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var deviceID: AudioDeviceID = 0
        var dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &deviceID
        )
        
        guard status == noErr else {
            return nil
        }
        
        return deviceID
    }
    
    func setOutputDevice(_ deviceName: String) -> Bool {
        // デフォルトの場合は何もしない
        if deviceName == "デフォルト" {
            return true
        }
        
        // デバイス名からdeviceIDを取得
        guard let device = availableOutputDevices.first(where: { $0.name == deviceName }),
              let deviceID = device.deviceID else {
            return false
        }
        
        // 現在のデバイスを保存（初回のみ）
        if originalOutputDeviceID == nil {
            originalOutputDeviceID = getCurrentOutputDeviceID()
        }
        
        // 出力デバイスを設定
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            dataSize,
            &deviceID
        )
        
        return status == noErr
    }
    
    func restoreOutputDevice() -> Bool {
        guard let originalDeviceID = originalOutputDeviceID else {
            return true // 元のデバイスが保存されていない場合は成功とみなす
        }
        
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        var deviceID = originalDeviceID
        let status = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            dataSize,
            &deviceID
        )
        
        originalOutputDeviceID = nil
        return status == noErr
    }
    
    private func getDisplayName(for deviceID: AudioDeviceID) -> String? {
        // ディスプレイ名を取得する試み
        // 実際の実装では、IOKitを使ってディスプレイ情報を取得する必要があります
        // ここでは簡易実装として、デバイス名から推測します
        
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var deviceName: CFString?
        var dataSize = UInt32(MemoryLayout<CFString?>.size)
        let status = AudioObjectGetPropertyData(
            deviceID,
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &deviceName
        )
        
        guard status == noErr, let name = deviceName as String? else {
            return nil
        }
        
        // HDMIやDisplayを含む場合は、そのまま返すか、より詳細な情報を取得
        if name.contains("HDMI") {
            // HDMI接続のモニタ名を取得（簡易版）
            return "HDMI接続モニタ"
        }
        
        return name
    }
    
    // MARK: - 設定の保存・読み込み
    func saveSettings() {
        let settings: [String: Any] = [
            "volume": volume,
            "outputDevice": outputDevice,
            "commandPath": commandPath,
            "commandArgs": commandArgs
        ]
        UserDefaults.standard.set(settings, forKey: settingsKey)
    }
    
    func loadSettings() {
        if let settings = UserDefaults.standard.dictionary(forKey: settingsKey) {
            if let vol = settings["volume"] as? Double {
                volume = vol
            }
            if let device = settings["outputDevice"] as? String {
                outputDevice = device
            }
            if let path = settings["commandPath"] as? String {
                commandPath = path
            }
            if let args = settings["commandArgs"] as? String {
                commandArgs = args
            }
        } else {
            // デフォルト値
            resetToDefault()
        }
    }
    
    func resetToDefault() {
        commandPath = "/usr/bin/open"
        commandArgs = "/Applications/Automator/AnnounceTime.app"
        volume = 30.0
        saveSettings()
    }
    
    // MARK: - ファイル選択
    func selectCommandFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.application, .executable]
        
        if panel.runModal() == .OK {
            if let url = panel.url {
                commandPath = url.path
                saveSettings()
            }
        }
    }
    
    // MARK: - コマンド実行
    func testCommand() {
        isRunning = true
        addLog("テスト実行を開始しました...", error: nil)
        
        let volumeController = VolumeController()
        volumeController.saveCurrentVolume()
        
        // 現在の出力デバイスを保存
        originalOutputDeviceID = getCurrentOutputDeviceID()
        
        // 出力デバイスを変更
        if outputDevice != "デフォルト" {
            if setOutputDevice(outputDevice) {
                addLog("出力先を \(outputDevice) に変更しました", error: nil)
            } else {
                addLog("出力先の変更に失敗しました", error: "出力先設定エラー")
            }
        }
        
        // 音量を変更
        if volumeController.setVolume(Int(volume)) {
            addLog("音量を \(Int(volume))% に変更しました", error: nil)
        } else {
            addLog("音量の変更に失敗しました", error: "音量設定エラー")
        }
        
        // コマンドを実行
        let task = Process()
        task.launchPath = "/bin/sh"
        
        var commandString = commandPath
        if !commandArgs.isEmpty {
            commandString += " \(commandArgs)"
        }
        task.arguments = ["-c", commandString]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        
        task.terminationHandler = { [weak self] process in
            DispatchQueue.main.async {
                guard let self = self else { return }
                
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let output = String(data: data, encoding: .utf8), !output.isEmpty {
                    self.addLog("出力: \(output)", error: nil)
                }
                
                if process.terminationStatus == 0 {
                    self.addLog("コマンドが正常に完了しました", error: nil)
                } else {
                    self.addLog("コマンドがエラーで終了しました", error: "終了コード: \(process.terminationStatus)")
                }
                
                // 出力デバイスを復元
                if self.restoreOutputDevice() {
                    self.addLog("出力先を元に戻しました", error: nil)
                } else {
                    self.addLog("出力先の復元に失敗しました", error: "出力先復元エラー")
                }
                
                // 音量を復元
                if volumeController.restoreVolume() {
                    self.addLog("音量を元に戻しました", error: nil)
                } else {
                    self.addLog("音量の復元に失敗しました", error: "音量復元エラー")
                }
                
                self.isRunning = false
            }
        }
        
        do {
            try task.run()
            addLog("コマンドを実行中: \(commandString)", error: nil)
        } catch {
            addLog("コマンドの実行に失敗しました", error: error.localizedDescription)
            isRunning = false
        }
    }
    
    // MARK: - LaunchAgent管理
    func checkLaunchAgentStatus() {
        let task = Process()
        task.launchPath = "/bin/launchctl"
        task.arguments = ["list"]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        
        do {
            try task.run()
            task.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                DispatchQueue.main.async {
                    self.launchAgentEnabled = output.contains(self.launchAgentPath)
                }
            }
        } catch {
            print("LaunchAgent状態確認エラー: \(error)")
        }
    }
    
    func toggleLaunchAgent(enabled: Bool) {
        let plistPath = "\(NSHomeDirectory())/Library/LaunchAgents/\(launchAgentFile)"
        
        if enabled {
            // LaunchAgentを有効化
            updateLaunchAgentPlist()
            let task = Process()
            task.launchPath = "/bin/launchctl"
            task.arguments = ["load", plistPath]
            
            do {
                try task.run()
                task.waitUntilExit()
                addLog("LaunchAgentを有効化しました", error: nil)
            } catch {
                addLog("LaunchAgentの有効化に失敗しました", error: error.localizedDescription)
            }
        } else {
            // LaunchAgentを無効化
            let task = Process()
            task.launchPath = "/bin/launchctl"
            task.arguments = ["unload", plistPath]
            
            do {
                try task.run()
                task.waitUntilExit()
                addLog("LaunchAgentを無効化しました", error: nil)
            } catch {
                addLog("LaunchAgentの無効化に失敗しました", error: error.localizedDescription)
            }
        }
        
        checkLaunchAgentStatus()
    }
    
    func updateLaunchAgentPlist() {
        let plistPath = "\(NSHomeDirectory())/Library/LaunchAgents/\(launchAgentFile)"
        let helperPath = "\(NSHomeDirectory())/bin/announce-helper"
        
        var arguments: [String] = [
            helperPath,
            "--volume",
            String(Int(volume)),
            "--"
        ]
        
        arguments.append(commandPath)
        if !commandArgs.isEmpty {
            arguments.append(contentsOf: commandArgs.split(separator: " ").map(String.init))
        }
        
        let plist: [String: Any] = [
            "Label": launchAgentPath,
            "ProgramArguments": arguments,
            "StartInterval": 900, // 15分
            "KeepAlive": false,
            "StandardOutPath": "/tmp/announcetime.log",
            "StandardErrorPath": "/tmp/announcetime.err"
        ]
        
        let data = try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try? data?.write(to: URL(fileURLWithPath: plistPath))
    }
    
    // MARK: - ログ管理
    func refreshLog() {
        let logPath = "/tmp/announce-helper.log"
        guard let content = try? String(contentsOfFile: logPath, encoding: .utf8) else {
            return
        }
        
        let lines = content.components(separatedBy: .newlines).filter { !$0.isEmpty }
        logEntries = lines.reversed().map { line in
            let parts = line.components(separatedBy: " | ")
            if parts.count >= 3 {
                let timestamp = parts[0]
                let message = parts.dropFirst().joined(separator: " | ")
                let error = message.contains("[エラー:") ? extractError(from: message) : nil
                return LogEntry(timestamp: timestamp, message: message, error: error)
            }
            return LogEntry(timestamp: "", message: line, error: nil)
        }
    }
    
    func clearLog() {
        let logPath = "/tmp/announce-helper.log"
        try? "".write(toFile: logPath, atomically: true, encoding: .utf8)
        logEntries = []
        addLog("ログをクリアしました", error: nil)
    }
    
    func addLog(_ message: String, error: String?) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let timestamp = formatter.string(from: Date())
        
        let entry = LogEntry(timestamp: timestamp, message: message, error: error)
        logEntries.append(entry)
        
        // ログファイルにも記録
        let logPath = "/tmp/announce-helper.log"
        let logLine = "\(timestamp) | \(message)\(error != nil ? " [エラー: \(error!)]" : "")\n"
        if let data = logLine.data(using: .utf8) {
            if let fileHandle = FileHandle(forWritingAtPath: logPath) {
                fileHandle.seekToEndOfFile()
                fileHandle.write(data)
                fileHandle.closeFile()
            } else {
                try? data.write(to: URL(fileURLWithPath: logPath), options: .atomic)
            }
        }
    }
    
    private func extractError(from message: String) -> String? {
        if let range = message.range(of: "[エラー: ") {
            let errorStart = message.index(range.upperBound, offsetBy: 0)
            if let errorEnd = message.range(of: "]", range: errorStart..<message.endIndex) {
                return String(message[errorStart..<errorEnd.lowerBound])
            }
        }
        return nil
    }
}

// MARK: - 音量制御（既存のコードから移植）
class VolumeController {
    private var originalVolume: Int?
    
    func getCurrentVolume() -> Int? {
        let script = """
        output volume of (get volume settings)
        """
        
        guard let appleScript = NSAppleScript(source: script) else {
            return nil
        }
        
        var error: NSDictionary?
        let result = appleScript.executeAndReturnError(&error)
        
        if let error = error {
            print("音量取得エラー: \(error)")
            return nil
        }
        
        return Int(result.int32Value)
    }
    
    func setVolume(_ volume: Int) -> Bool {
        guard volume >= 0 && volume <= 100 else {
            return false
        }
        
        let script = """
        set volume output volume \(volume)
        """
        
        guard let appleScript = NSAppleScript(source: script) else {
            return false
        }
        
        var error: NSDictionary?
        appleScript.executeAndReturnError(&error)
        
        if let error = error {
            print("音量設定エラー: \(error)")
            return false
        }
        
        return true
    }
    
    func saveCurrentVolume() {
        originalVolume = getCurrentVolume()
    }
    
    func restoreVolume() -> Bool {
        guard let volume = originalVolume else {
            return false
        }
        return setVolume(volume)
    }
}

