import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        VSplitView {
            // 上: 設定パネル
            SettingsPanel()
            
            Divider()
            
            // 下: ログ表示（150px固定）
            LogView()
                .frame(height: 150)
        }
        .frame(minWidth: 750, minHeight: 600)
    }
}

struct SettingsPanel: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        VStack(spacing: 0) {
            // ヘッダー（テスト実行ボタンを「時間読み上げヘルパー」から右に150px）
            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: "speaker.wave.3.fill")
                            .font(.title)
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.blue, .purple],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                        Text("時間読み上げヘルパー")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                    }
                    Text("音量調整とコマンド実行を管理")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                // 75pxのスペース（150pxの半分）
                Spacer()
                    .frame(width: 75)
                
                // テスト実行ボタン（タイトルの高さに合わせる）
                Button(action: {
                    appState.testCommand()
                }) {
                    HStack(spacing: 4) {
                        if appState.isRunning {
                            ProgressView()
                                .scaleEffect(0.7)
                                .progressViewStyle(.circular)
                        } else {
                            Image(systemName: "play.fill")
                                .font(.system(size: 14))
                        }
                        if !appState.isRunning {
                            Text("実行")
                                .font(.system(size: 13, weight: .medium))
                        }
                    }
                    .frame(width: 50)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .disabled(appState.isRunning || appState.commandPath.isEmpty)
                .tint(Color(red: 0.25, green: 0.88, blue: 0.82)) // ターコイズ
                
                Spacer()
            }
            .padding(24)
            .padding(.bottom, 8)
            
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // 音量設定カード
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Image(systemName: "slider.horizontal.3")
                                .foregroundColor(.blue)
                            Text("一時音量設定")
                                .font(.headline)
                        }
                        
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("音量")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text("\(Int(appState.volume))%")
                                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                                    .foregroundColor(.blue)
                                    .monospacedDigit()
                                    .frame(minWidth: 60, alignment: .trailing)
                            }
                            
                            Slider(value: $appState.volume, in: 0...100, step: 1)
                                .tint(.blue)
                                .onChange(of: appState.volume) { newValue in
                                    appState.saveSettings()
                                }
                            
                            // クイック設定ボタン
                            HStack(spacing: 8) {
                                QuickVolumeButton(value: 10, current: $appState.volume)
                                QuickVolumeButton(value: 30, current: $appState.volume)
                                QuickVolumeButton(value: 50, current: $appState.volume)
                                QuickVolumeButton(value: 70, current: $appState.volume)
                                QuickVolumeButton(value: 100, current: $appState.volume)
                            }
                        }
                    }
                    .padding(20)
                    .background {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(NSColor.controlBackgroundColor))
                            .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
                    }
                
                // 出力先設定カード
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Image(systemName: "speaker.wave.2.fill")
                            .foregroundColor(.purple)
                        Text("出力先設定")
                            .font(.headline)
                    }
                    
                    VStack(alignment: .leading, spacing: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("音声出力先")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Picker("", selection: $appState.outputDevice) {
                                ForEach(appState.availableOutputDevices) { device in
                                    Text(device.name).tag(device.name)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .onChange(of: appState.outputDevice) { _ in
                                appState.saveSettings()
                            }
                            
                            Button(action: {
                                appState.loadAvailableOutputDevices()
                            }) {
                                HStack {
                                    Image(systemName: "arrow.clockwise")
                                        .font(.caption)
                                    Text("デバイスを更新")
                                        .font(.caption)
                                }
                            }
                            .buttonStyle(.borderless)
                            
                        }
                    }
                }
                .padding(20)
                .background {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(NSColor.controlBackgroundColor))
                        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
                }
                
                // コマンド設定カード
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Image(systemName: "terminal.fill")
                            .foregroundColor(.green)
                        Text("実行コマンド")
                            .font(.headline)
                    }
                    
                    VStack(alignment: .leading, spacing: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("コマンドパス")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            HStack(spacing: 8) {
                                TextField("", text: $appState.commandPath)
                                    .textFieldStyle(.plain)
                                    .padding(10)
                                    .background(Color(NSColor.textBackgroundColor))
                                    .cornerRadius(8)
                                    .onChange(of: appState.commandPath) { _ in
                                        appState.saveSettings()
                                    }
                                
                                Button(action: {
                                    appState.selectCommandFile()
                                }) {
                                    Image(systemName: "folder.fill")
                                        .font(.system(size: 14))
                                }
                                .buttonStyle(.bordered)
                                .help("ファイルを選択")
                            }
                        }
                        
                        VStack(alignment: .leading, spacing: 6) {
                            Text("コマンド引数（オプション）")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            TextField("引数をスペース区切りで入力", text: $appState.commandArgs)
                                .textFieldStyle(.plain)
                                .padding(10)
                                .background(Color(NSColor.textBackgroundColor))
                                .cornerRadius(8)
                                .onChange(of: appState.commandArgs) { _ in
                                    appState.saveSettings()
                                }
                        }
                        
                        HStack {
                            Text("例: /usr/bin/open /Applications/Automator/AnnounceTime.app")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            Button("デフォルトに戻す") {
                                appState.resetToDefault()
                            }
                            .buttonStyle(.borderless)
                            .font(.caption)
                        }
                    }
                }
                .padding(20)
                .background {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(NSColor.controlBackgroundColor))
                        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
                }
                
                // LaunchAgent設定カード
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Image(systemName: "clock.fill")
                            .foregroundColor(.orange)
                        Text("自動実行設定")
                            .font(.headline)
                    }
                    
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("LaunchAgent")
                                    .font(.subheadline)
                                if appState.launchAgentEnabled {
                                    Text("15分ごとに自動実行されます")
                                        .font(.caption)
                                        .foregroundColor(.green)
                                } else {
                                    Text("自動実行は無効です")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            Spacer()
                            Toggle("", isOn: $appState.launchAgentEnabled)
                                .toggleStyle(.switch)
                                .labelsHidden()
                                .onChange(of: appState.launchAgentEnabled) { newValue in
                                    appState.toggleLaunchAgent(enabled: newValue)
                                }
                        }
                    }
                }
                .padding(20)
                .background {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(NSColor.controlBackgroundColor))
                        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
                }
                
                    // ステータス表示
                    StatusView()
                        .environmentObject(appState)
                }
                .padding(24)
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
    }
}

struct QuickVolumeButton: View {
    let value: Int
    @Binding var current: Double
    
    var isSelected: Bool {
        Int(current) == value
    }
    
    var body: some View {
        Button(action: {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                current = Double(value)
            }
        }) {
            Text("\(value)%")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(isSelected ? .white : .primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isSelected ? Color.blue : Color(NSColor.controlBackgroundColor))
                }
        }
        .buttonStyle(.plain)
    }
}

struct StatusView: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(appState.launchAgentEnabled ? Color.green : Color.gray)
                .frame(width: 8, height: 8)
            
            Text(appState.launchAgentEnabled ? "自動実行: 有効" : "自動実行: 無効")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Spacer()
            
            if appState.isRunning {
                HStack(spacing: 4) {
                    ProgressView()
                        .scaleEffect(0.6)
                        .progressViewStyle(.circular)
                    Text("実行中")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.controlBackgroundColor).opacity(0.5))
        }
    }
}

struct LogView: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // ヘッダー
            HStack {
                Image(systemName: "doc.text.fill")
                    .foregroundColor(.blue)
                Text("実行ログ")
                    .font(.headline)
                Spacer()
                
                HStack(spacing: 8) {
                    Button(action: {
                        appState.refreshLog()
                    }) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 14))
                    }
                    .buttonStyle(.borderless)
                    .help("更新")
                    
                    Button(action: {
                        appState.clearLog()
                    }) {
                        Image(systemName: "trash")
                            .font(.system(size: 14))
                    }
                    .buttonStyle(.borderless)
                    .help("クリア")
                }
            }
            .padding(20)
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // ログコンテンツ
            if appState.logEntries.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text("ログがありません")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Text("テスト実行するとログが表示されます")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    ScrollViewReader { proxy in
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(appState.logEntries) { entry in
                                LogEntryView(entry: entry)
                                    .id(entry.id)
                            }
                        }
                        .padding(20)
                        .onChange(of: appState.logEntries.count) { _ in
                            if let last = appState.logEntries.last {
                                withAnimation(.easeOut(duration: 0.3)) {
                                    proxy.scrollTo(last.id, anchor: .bottom)
                                }
                            }
                        }
                    }
                }
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
    }
}

struct LogEntryView: View {
    let entry: AppState.LogEntry
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: entry.hasError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(entry.hasError ? .orange : .green)
                    
                    Text(entry.timestamp)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            
            Text(entry.message)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .foregroundColor(.primary)
            
            if let error = entry.error {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 10))
                    Text(error)
                        .font(.caption)
                }
                .foregroundColor(.red)
                .padding(.top, 4)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 8)
                .fill(entry.hasError ? Color.red.opacity(0.1) : Color(NSColor.controlBackgroundColor))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(entry.hasError ? Color.red.opacity(0.3) : Color.clear, lineWidth: 1)
                }
        }
    }
}
