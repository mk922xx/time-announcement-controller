import SwiftUI
import Foundation
import AppKit
import CoreAudio

class AppState: ObservableObject {
    @Published var volume: Double = 30.0
    @Published var outputDevice: String = "Macminiのスピーカー"
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
    private var originalSystemOutputDeviceID: AudioDeviceID?
    
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
            addLog("デバイス情報の取得に失敗しました", error: "OSStatus: \(status)")
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
            addLog("デバイスID一覧の取得に失敗しました", error: "OSStatus: \(status)")
            return
        }
        
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
            
            // デバイスUIDを取得
            var uidAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceUID,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            
            var deviceUIDValue: Unmanaged<CFString>?
            var uidDataSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            status = AudioObjectGetPropertyData(
                deviceID,
                &uidAddress,
                0,
                nil,
                &uidDataSize,
                &deviceUIDValue
            )
            
            let uidString = (deviceUIDValue?.takeRetainedValue() as String?) ?? "\(deviceID)"
            
            // デバイス名を取得
            propertyAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceNameCFString,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            
｀            var deviceName: Unmanaged<CFString>?
            var nameDataSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            status = AudioObjectGetPropertyData(
                deviceID,
                &propertyAddress,
                0,
                nil,
                &nameDataSize,
                &deviceName
            )
            
            if let unmanagedName = deviceName, let name = unmanagedName.takeRetainedValue() as String? {
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
                
                devices.append(AudioDevice(id: uidString, name: displayName, uid: uidString, deviceID: deviceID))
            }
        }
        
        availableOutputDevices = devices
        
        // 現在のデバイスがリストにない場合はMacminiのスピーカーに設定
        if !devices.contains(where: { $0.name == outputDevice }) {
            if let macminiDevice = devices.first(where: { $0.name == "Macminiのスピーカー" }) {
                outputDevice = macminiDevice.name
            } else if let firstDevice = devices.first {
                outputDevice = firstDevice.name
            }
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
    
    private func getCurrentSystemOutputDeviceID() -> AudioDeviceID? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultSystemOutputDevice,
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
    
    private func setDefaultDevice(_ deviceID: AudioDeviceID, selector: AudioObjectPropertySelector) -> OSStatus {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        let dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        var mutableDeviceID = deviceID
        return AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            dataSize,
            &mutableDeviceID
        )
    }
    
    func setOutputDevice(_ deviceName: String) -> Bool {
        // デバイス名からdeviceIDを取得
        guard let device = availableOutputDevices.first(where: { $0.name == deviceName }),
              let deviceID = device.deviceID else {
            addLog("デバイス \(deviceName) が見つかりません", error: "デバイス検索エラー")
            return false
        }
        
        // 現在のデバイスを保存（初回のみ）
        if originalOutputDeviceID == nil {
            originalOutputDeviceID = getCurrentOutputDeviceID()
        }
        if originalSystemOutputDeviceID == nil {
            originalSystemOutputDeviceID = getCurrentSystemOutputDeviceID()
        }
        
        // まず、switchaudiosourceコマンドを試す（より確実）
        if let deviceUID = getDeviceUID(deviceID: deviceID),
           let actualDeviceName = getActualDeviceName(deviceUID: deviceUID) {
            addLog("switchaudiosourceで出力先を変更します: \(actualDeviceName)", error: nil)
            if setOutputDeviceWithCommand(deviceName: actualDeviceName, displayName: deviceName) {
                return true
            }
            addLog("switchaudiosourceでの変更に失敗しました。CoreAudioを試します...", error: nil)
        } else {
            addLog("デバイス情報の取得に失敗しました。CoreAudioを試します...", error: nil)
        }
        
        // switchaudiosourceが使えない場合、CoreAudioで直接設定を試みる
        let outputStatus = setDefaultDevice(deviceID, selector: kAudioHardwarePropertyDefaultOutputDevice)
        let systemStatus = setDefaultDevice(deviceID, selector: kAudioHardwarePropertyDefaultSystemOutputDevice)
        
        if outputStatus != noErr || systemStatus != noErr {
            addLog("CoreAudioで出力先変更に失敗しました", error: "出力:\(outputStatus), システム:\(systemStatus)")
            addLog("ヒント: switchaudiosourceをインストールしてください: brew install switchaudio-osx", error: nil)
            return false
        }
        
        // 少し待ってから変更が反映されたか確認
        Thread.sleep(forTimeInterval: 0.2)
        let currentDeviceID = getCurrentOutputDeviceID()
        let currentSystemDeviceID = getCurrentSystemOutputDeviceID()
        if currentDeviceID == deviceID && currentSystemDeviceID == deviceID {
            addLog("出力先を \(deviceName) に変更しました (CoreAudio)", error: nil)
            return true
        } else {
            addLog("出力先の変更が確認できませんでした", error: "変更が反映されませんでした")
            return false
        }
    }
    
    private func getDeviceUID(deviceID: AudioDeviceID) -> String? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var deviceUID: Unmanaged<CFString>?
        var dataSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = AudioObjectGetPropertyData(
            deviceID,
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &deviceUID
        )
        
        guard status == noErr, let unmanagedUID = deviceUID, let uid = unmanagedUID.takeRetainedValue() as String? else {
            return nil
        }
        
        return uid
    }
    
    private func setOutputDeviceWithCommand(deviceName: String, displayName: String) -> Bool {
        // switchaudiosourceコマンドを試す（Homebrewでインストール可能: brew install switchaudio-osx）
        let switchAudioSourcePath = "/usr/local/bin/switchaudiosource"
        let altPath = "/opt/homebrew/bin/switchaudiosource"
        
        var commandPath: String?
        if FileManager.default.fileExists(atPath: switchAudioSourcePath) {
            commandPath = switchAudioSourcePath
        } else if FileManager.default.fileExists(atPath: altPath) {
            commandPath = altPath
        }
        
        if let path = commandPath {
            let task = Process()
            task.launchPath = path
            task.arguments = ["-t", "output", "-s", deviceName]
            
            do {
                try task.run()
                task.waitUntilExit()
                
                if task.terminationStatus == 0 {
                    // 少し待ってから確認
                    Thread.sleep(forTimeInterval: 0.2)
                    let currentDeviceID = getCurrentOutputDeviceID()
                    let currentSystemDeviceID = getCurrentSystemOutputDeviceID()
                    if let device = availableOutputDevices.first(where: { $0.name == displayName }),
                       let targetDeviceID = device.deviceID,
                       currentDeviceID == targetDeviceID,
                       currentSystemDeviceID == targetDeviceID {
                        addLog("出力先を \(displayName) に変更しました (switchaudiosource)", error: nil)
                        return true
                    } else {
                        addLog("出力先の変更が確認できませんでした", error: "変更が反映されませんでした")
                    }
                } else {
                    addLog("switchaudiosourceで出力先変更に失敗しました", error: "終了コード: \(task.terminationStatus)")
                }
            } catch {
                addLog("switchaudiosourceの実行に失敗しました", error: error.localizedDescription)
            }
        } else {
            addLog("switchaudiosourceが見つかりません。Homebrewでインストールしてください: brew install switchaudio-osx", error: nil)
        }
        
        return false
    }
    
    private func getActualDeviceName(deviceUID: String) -> String? {
        // UIDからデバイスIDを取得
        guard let device = availableOutputDevices.first(where: { $0.uid == deviceUID }),
              let deviceID = device.deviceID else {
            return nil
        }
        
        // デバイスの実際の名前を取得
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var deviceName: Unmanaged<CFString>?
        var dataSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = AudioObjectGetPropertyData(
            deviceID,
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &deviceName
        )
        
        guard status == noErr, let unmanagedName = deviceName, let name = unmanagedName.takeRetainedValue() as String? else {
            return nil
        }
        
        return name
    }
    
    func restoreOutputDevice() -> Bool {
        var success = true
        
        if let originalDeviceID = originalOutputDeviceID {
            success = success && (setDefaultDevice(originalDeviceID, selector: kAudioHardwarePropertyDefaultOutputDevice) == noErr)
        }
        if let originalSystemDeviceID = originalSystemOutputDeviceID {
            success = success && (setDefaultDevice(originalSystemDeviceID, selector: kAudioHardwarePropertyDefaultSystemOutputDevice) == noErr)
        }
        
        originalOutputDeviceID = nil
        originalSystemOutputDeviceID = nil
        return success
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
        
        var deviceName: Unmanaged<CFString>?
        var dataSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = AudioObjectGetPropertyData(
            deviceID,
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &deviceName
        )
        
        guard status == noErr, let unmanagedName = deviceName, let name = unmanagedName.takeRetainedValue() as String? else {
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
                // 「デフォルト」が保存されていた場合はMacminiのスピーカーに変更
                if device == "デフォルト" {
                    outputDevice = "Macminiのスピーカー"
                } else {
                    outputDevice = device
                }
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
        outputDevice = "Macminiのスピーカー"
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
        let currentDeviceBefore = getCurrentOutputDeviceID()
        addLog("現在の出力先ID: \(currentDeviceBefore ?? 0)", error: nil)
        
        if setOutputDevice(outputDevice) {
            // 変更後の出力先を確認
            Thread.sleep(forTimeInterval: 0.5)
            let currentDeviceAfter = getCurrentOutputDeviceID()
            if let device = availableOutputDevices.first(where: { $0.name == outputDevice }),
               let targetDeviceID = device.deviceID {
                if currentDeviceAfter == targetDeviceID {
                    addLog("出力先を \(outputDevice) に変更しました (確認ID: \(currentDeviceAfter ?? 0))", error: nil)
                } else {
                    addLog("出力先の変更が確認できませんでした", error: "変更が反映されませんでした")
                    addLog("現在の出力先ID: \(currentDeviceAfter ?? 0), 期待値: \(targetDeviceID)", error: nil)
                    addLog("switchaudiosourceをインストールしてください: brew install switchaudio-osx", error: nil)
                }
            } else {
                addLog("出力先を \(outputDevice) に変更しました", error: nil)
            }
        } else {
            addLog("出力先の変更に失敗しました", error: "出力先設定エラー")
            addLog("switchaudiosourceをインストールしてください: brew install switchaudio-osx", error: nil)
        }
        
        // 音量を変更
        let currentVolBefore = volumeController.getCurrentVolume()
        addLog("現在の音量: \(currentVolBefore ?? -1)%", error: nil)
        
        if currentVolBefore == nil {
            addLog("⚠️ 音量の取得に失敗しました。アクセシビリティの権限を確認してください", error: "権限エラー")
            addLog("システム設定 > プライバシーとセキュリティ > アクセシビリティ でアプリを有効にしてください", error: nil)
        }
        
        if volumeController.setVolume(Int(volume)) {
            // 変更後の音量を確認
            Thread.sleep(forTimeInterval: 0.3)
            let currentVolAfter = volumeController.getCurrentVolume()
            addLog("音量を \(Int(volume))% に設定しました (確認: \(currentVolAfter ?? -1)%)", error: nil)
            
            if let after = currentVolAfter {
                if abs(after - Int(volume)) > 2 {
                    addLog("警告: 音量が期待値と異なります", error: "設定値: \(Int(volume))%, 実際の値: \(after)%")
                    addLog("アクセシビリティの権限が正しく設定されているか確認してください", error: nil)
                }
            } else {
                addLog("警告: 音量の確認に失敗しました", error: "音量確認エラー")
            }
        } else {
            addLog("音量の変更に失敗しました", error: "音量設定エラー")
            addLog("アクセシビリティの権限が必要です", error: nil)
            addLog("システム設定 > プライバシーとセキュリティ > アクセシビリティ でアプリを有効にしてください", error: nil)
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
        
        // VolumeControllerを保持（クロージャで使用するため）
        let volumeControllerRef = volumeController
        
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
                let restoredVol = volumeControllerRef.restoreVolume()
                if restoredVol {
                    let currentVol = volumeControllerRef.getCurrentVolume()
                    self.addLog("音量を元に戻しました (確認: \(currentVol ?? -1)%)", error: nil)
                } else {
                    self.addLog("音量の復元に失敗しました", error: "音量復元エラー")
                    // 元の音量を再試行
                    if let originalVol = volumeControllerRef.originalVolume {
                        self.addLog("音量復元を再試行します: \(originalVol)%", error: nil)
                        _ = volumeControllerRef.setVolume(originalVol)
                    }
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
    var originalVolume: Int? // デバッグ用に公開
    
    func getCurrentVolume() -> Int? {
        // NSAppleScriptを使用（より確実な方法）
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
        
        // NSAppleScriptを使用（より確実な方法）
        let script = """
        set volume output volume \(volume)
        """
        
        guard let appleScript = NSAppleScript(source: script) else {
            print("エラー: AppleScriptの作成に失敗しました")
            return false
        }
        
        var error: NSDictionary?
        appleScript.executeAndReturnError(&error)
        
        if let error = error {
            let errorCode = error[NSAppleScript.errorNumber] as? Int ?? -1
            let errorMessage = error[NSAppleScript.errorMessage] as? String ?? "不明なエラー"
            print("音量設定エラー: コード=\(errorCode), メッセージ=\(errorMessage)")
            
            // 権限エラーの場合
            if errorCode == -1743 || errorMessage.contains("not allowed") {
                print("⚠️ アクセシビリティの権限が必要です。システム設定 > プライバシーとセキュリティ > アクセシビリティ でアプリを有効にしてください。")
            }
            return false
        }
        
        // 設定が反映されたか確認
        Thread.sleep(forTimeInterval: 0.2)
        let currentVolume = getCurrentVolume()
        if let current = currentVolume {
            if abs(current - volume) <= 2 {
                return true
            } else {
                print("警告: 音量設定が反映されていません。設定値: \(volume)%, 実際の値: \(current)%")
            }
        }
        
        return true // エラーがなければ成功とみなす
    }
    
    func saveCurrentVolume() {
        originalVolume = getCurrentVolume()
    }
    
    func restoreVolume() -> Bool {
        guard let volume = originalVolume else {
            print("警告: 元の音量が保存されていません")
            return false
        }
        print("音量を元に戻します: \(volume)%")
        return setVolume(volume)
    }
}

