import Foundation
import AppKit

// MARK: - 音量制御
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
            print("音量取得エラー: \(error)", to: &standardError)
            return nil
        }
        
        return result.int32Value != nil ? Int(result.int32Value) : nil
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
            print("音量設定エラー: \(error)", to: &standardError)
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

// MARK: - 出力先制御
class OutputDeviceController {
    private var originalDevice: String?
    
    func getCurrentOutputDevice() -> String? {
        let script = """
        tell application "System Events"
            tell process "System Settings"
                -- 出力デバイス名を取得
                set currentDevice to name of current audio output device
                return currentDevice
            end tell
        end tell
        """
        
        // より確実な方法: system_profiler を使用
        let task = Process()
        task.launchPath = "/usr/sbin/system_profiler"
        task.arguments = ["SPAudioDataType"]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        
        do {
            try task.run()
            task.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                // 出力デバイス名を抽出（簡易版）
                // 実際の実装では、より詳細な解析が必要
                return "default"
            }
        } catch {
            return nil
        }
        
        return nil
    }
    
    func setOutputDevice(_ deviceName: String) -> Bool {
        // macOS の出力デバイス変更は複雑なため、
        // ここでは簡易実装として、システム設定を開く方法を提供
        // 実際のデバイス変更には CoreAudio フレームワークが必要
        
        // 簡易実装: デバイス名を保存のみ
        originalDevice = getCurrentOutputDevice()
        return true
    }
    
    func saveCurrentOutputDevice() {
        originalDevice = getCurrentOutputDevice()
    }
    
    func restoreOutputDevice() -> Bool {
        // 実装は簡易版のため、実際の復元は行わない
        // 必要に応じて CoreAudio を使用した実装に拡張可能
        return true
    }
}

// MARK: - ログ出力
class Logger {
    private let logPath = "/tmp/announce-helper.log"
    
    func log(timestamp: Date, volume: Int?, outputDevice: String?, command: String, error: String? = nil) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let timeString = formatter.string(from: timestamp)
        
        let volumeStr = volume != nil ? "\(volume!)" : "未変更"
        let deviceStr = outputDevice != nil ? outputDevice! : "未変更"
        let commandPreview = String(command.prefix(50))
        let errorStr = error != nil ? " [エラー: \(error!)]" : ""
        
        let logLine = "\(timeString) | 音量: \(volumeStr) | 出力先: \(deviceStr) | コマンド: \(commandPreview)\(errorStr)\n"
        
        if let data = logLine.data(using: .utf8) {
            if let fileHandle = FileHandle(forWritingAtPath: logPath) {
                fileHandle.seekToEndOfFile()
                fileHandle.write(data)
                fileHandle.closeFile()
            } else {
                // ファイルが存在しない場合は作成
                try? data.write(to: URL(fileURLWithPath: logPath), options: .atomic)
            }
        }
    }
}

// MARK: - コマンドライン引数解析
struct Arguments {
    var command: [String] = []
    var volume: Int?
    var outputDevice: String?
    
    static func parse() -> Arguments? {
        var args = Arguments()
        let arguments = CommandLine.arguments
        
        var i = 1
        while i < arguments.count {
            let arg = arguments[i]
            
            switch arg {
            case "--volume":
                if i + 1 < arguments.count, let vol = Int(arguments[i + 1]), vol >= 0 && vol <= 100 {
                    args.volume = vol
                    i += 2
                } else {
                    return nil
                }
            case "--output-device", "--output":
                if i + 1 < arguments.count {
                    args.outputDevice = arguments[i + 1]
                    i += 2
                } else {
                    return nil
                }
            case "--":
                // -- 以降はすべてコマンド引数
                i += 1
                while i < arguments.count {
                    args.command.append(arguments[i])
                    i += 1
                }
                break
            default:
                // オプションでない場合はコマンドの開始
                if !arg.hasPrefix("--") {
                    while i < arguments.count {
                        args.command.append(arguments[i])
                        i += 1
                    }
                    break
                } else {
                    i += 1
                }
            }
        }
        
        return args.command.isEmpty ? nil : args
    }
    
    static func printUsage() {
        let usage = """
        使い方: announce-helper [オプション] -- コマンド [コマンド引数...]
        
        オプション:
          --volume 30              一時的に設定する出力音量 (0-100)
          --output-device NAME     一時的に設定する出力デバイス名（将来実装予定）
        
        例:
          announce-helper --volume 30 -- /usr/bin/open /Applications/Automator/AnnounceTime.app
          announce-helper --volume 40 -- say "テストです"
        
        注意:
          -- の後に実行するコマンドとその引数を指定してください
        """
        print(usage)
    }
}

// MARK: - 標準エラー出力
var standardError = FileHandle.standardError

extension FileHandle: TextOutputStream {
    public func write(_ string: String) {
        guard let data = string.data(using: .utf8) else { return }
        self.write(data)
    }
}

// MARK: - メイン処理
func main() {
    guard let args = Arguments.parse() else {
        Arguments.printUsage()
        exit(1)
    }
    
    let volumeController = VolumeController()
    let outputDeviceController = OutputDeviceController()
    let logger = Logger()
    let startTime = Date()
    var errorMessage: String? = nil
    
    // 現在の音量と出力先を保存
    volumeController.saveCurrentVolume()
    outputDeviceController.saveCurrentOutputDevice()
    
    // 一時音量を設定
    if let volume = args.volume {
        if !volumeController.setVolume(volume) {
            errorMessage = "音量設定に失敗"
            print("エラー: 音量設定に失敗しました", to: &standardError)
        }
    }
    
    // 出力先を設定（将来実装）
    if let device = args.outputDevice {
        if !outputDeviceController.setOutputDevice(device) {
            if errorMessage == nil {
                errorMessage = "出力先設定に失敗"
            }
            print("警告: 出力先設定に失敗しました（機能は将来実装予定）", to: &standardError)
        }
    }
    
    // コマンドを実行
    let commandString = args.command.joined(separator: " ")
    let task = Process()
    task.launchPath = "/bin/sh"
    task.arguments = ["-c", commandString]
    
    // 標準出力と標準エラーを継承
    task.standardOutput = FileHandle.standardOutput
    task.standardError = FileHandle.standardError
    
    do {
        try task.run()
        task.waitUntilExit()
        
        if task.terminationStatus != 0 {
            errorMessage = "コマンド実行エラー (終了コード: \(task.terminationStatus))"
        }
    } catch {
        errorMessage = "コマンド実行エラー: \(error.localizedDescription)"
        print("エラー: \(errorMessage!)", to: &standardError)
    }
    
    // 音量を元に戻す
    if !volumeController.restoreVolume() {
        if errorMessage == nil {
            errorMessage = "音量復元に失敗"
        }
        print("警告: 音量の復元に失敗しました", to: &standardError)
    }
    
    // 出力先を元に戻す
    _ = outputDeviceController.restoreOutputDevice()
    
    // ログに記録
    logger.log(timestamp: startTime, volume: args.volume, outputDevice: args.outputDevice, command: commandString, error: errorMessage)
    
    // エラーがあった場合は非ゼロで終了
    if errorMessage != nil {
        exit(1)
    }
}

main()
