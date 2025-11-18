# 時間読み上げ用ヘルパーアプリ

macOS 26.1 (Apple Silicon) で動作する、既存の読み上げコマンドをラップして音量と出力先を制御するコマンドラインツールです。
既存の読み上げスクリプト（Automator アプリなど）を実行する前に音量を一時的に変更し、実行後に元の音量に戻します。

## 機能

- 現在のシステム音量を保存
- オプションで一時音量を設定
- 既存のコマンド（Automator アプリなど）を実行
- コマンド実行後に音量を自動復元
- エラー時も可能な限り音量を復元
- 実行ログを `/tmp/announce-helper.log` に記録
- 出力先の変更（将来実装予定）

## セットアップ

### 1. プロジェクトのビルド

```bash
cd "/Users/moto/cursor/Time Announcement Controller Apps"
swift build -c release
```

### 2. バイナリの配置

ビルドが完了したら、バイナリを `~/bin/` に配置します：

```bash
cp .build/release/announce-helper ~/bin/announce-helper
chmod +x ~/bin/announce-helper
```

### 3. 動作確認

```bash
announce-helper --volume 30 -- /usr/bin/open /Applications/Automator/AnnounceTime.app
```

## 使い方

### 基本的な使い方

既存のコマンドを `--` の後に指定します：

```bash
announce-helper --volume 30 -- /usr/bin/open /Applications/Automator/AnnounceTime.app
```

この場合、Automator アプリを実行する前に音量が30%に変更され、実行後に元の音量に戻ります。

### コマンドライン引数

- **必須:**
  - `--` の後に実行するコマンドとその引数を指定

- **オプション:**
  - `--volume 30` - 一時的に設定する出力音量 (0-100)
  - `--output-device NAME` - 一時的に設定する出力デバイス名（将来実装予定）

### 使用例

#### Automator アプリを音量30%で実行

```bash
announce-helper --volume 30 -- /usr/bin/open /Applications/Automator/AnnounceTime.app
```

#### say コマンドを音量40%で実行

```bash
announce-helper --volume 40 -- say "テストです"
```

#### 複数の引数を持つコマンドを実行

```bash
announce-helper --volume 35 -- /path/to/script.sh arg1 arg2
```

## LaunchAgent の設定

既存の LaunchAgent（`com.moto.announcetime.plist`）を修正して、このヘルパーアプリを使用するように変更します。

### 既存の LaunchAgent を更新

```bash
# 既存の LaunchAgent を停止
launchctl unload ~/Library/LaunchAgents/com.moto.announcetime.plist

# plist ファイルを編集して、以下のように変更：
# ProgramArguments を以下に変更：
# <array>
#     <string>/Users/moto/bin/announce-helper</string>
#     <string>--volume</string>
#     <string>30</string>
#     <string>--</string>
#     <string>/usr/bin/open</string>
#     <string>/Applications/Automator/AnnounceTime.app</string>
# </array>

# LaunchAgent を再読み込み
launchctl load ~/Library/LaunchAgents/com.moto.announcetime.plist
```

### 新しい LaunchAgent のサンプル

`com.timeannounce.helper.plist` を参考にしてください。

## ログ

実行ログは `/tmp/announce-helper.log` に記録されます。

ログの形式：
```
2024-11-18 16:30:00 | 音量: 30 | 出力先: 未変更 | コマンド: /usr/bin/open /Applications/Automator/AnnounceTime.app
```

## トラブルシューティング

### 音量が復元されない場合

- アプリケーションに音量制御の権限が必要な場合があります
- システム環境設定 > セキュリティとプライバシー > プライバシー > アクセシビリティ でターミナルやコマンドラインツールにアクセス権限を付与してください

### コマンドが実行されない場合

- `--` の後にコマンドを正しく指定しているか確認してください
- コマンドのパスが正しいか確認してください
- エラーログを確認してください：`cat /tmp/announce-helper.err.log`

## 開発

### プロジェクト構造

```
.
├── Package.swift
├── Sources/
│   └── announce-helper/
│       └── main.swift
├── README.md
└── com.timeannounce.helper.plist
```

### ビルドとテスト

```bash
# デバッグビルド
swift build

# リリースビルド
swift build -c release

# 実行テスト
swift run announce-helper --volume 30 -- say "テスト"
```
