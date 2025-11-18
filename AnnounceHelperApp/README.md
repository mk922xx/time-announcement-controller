# AnnounceHelperApp - GUIアプリケーション

時間読み上げヘルパーのGUIアプリケーションです。

## ビルド方法

### 方法1: Xcodeで開く（推奨）

1. Xcodeで `AnnounceHelperApp.xcodeproj` を開く
2. プロダクト > ビルド（⌘B）
3. プロダクト > 実行（⌘R）

### 方法2: コマンドラインでビルド

```bash
cd AnnounceHelperApp
xcodebuild -project AnnounceHelperApp.xcodeproj -scheme AnnounceHelperApp -configuration Release
```

ビルドされたアプリは `build/Release/AnnounceHelperApp.app` にあります。

## 機能

- **音量調整**: スライダーで一時音量を設定（0-100%）
- **コマンド設定**: 実行するコマンドと引数を設定
- **テスト実行**: 設定したコマンドをテスト実行
- **ログ表示**: 実行ログをリアルタイムで表示
- **LaunchAgent管理**: 自動実行の有効/無効を切り替え

## 使い方

1. アプリを起動
2. 音量スライダーで一時音量を設定
3. コマンドパスと引数を設定（デフォルトは Automator アプリ）
4. 「テスト実行」ボタンで動作確認
5. LaunchAgentのトグルで自動実行を有効化

## 設定の保存

設定は自動的に保存され、次回起動時に復元されます。

