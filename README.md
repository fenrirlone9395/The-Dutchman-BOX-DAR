# The Dutchman BOX/DAR

macOSで再生している音を、好きなAudio Unitへ通して聴くためのスタンドアロンAudio Rackです。

![Rack First UI](preview-rack-eight.png)

## 現在のバージョン

**0.0.12** — Apple Silicon / macOS 14以降。元音声をミュートするSystem AudioモードはmacOS 14.2以降。

- System AudioをCore Audio Process Tapで取得。取得中は元音声をミュートし、自アプリの出力は除外。
- アプリ単位の取得はScreenCaptureKitの標準ピッカーを使用。
- AUv2 Stereo Effectを最大8個追加。再生中の追加・削除・並べ替えに対応。
- メーカーの純正GUIをフローティング表示。純正GUIがない場合はAUGenericViewへフォールバック。
- Factory Preset、インストール済み`.aupreset`、ファイル指定による読み込み。
- 現在のプリセット表示、チェックマーク、編集状態、−／＋によるザッピング。
- Input Gain、15バンドMaster GEQ、Master Gain、左右連動Limiter、Emergency Mute。
- AU Rackの種類・順序・プラグイン状態・プリセット情報を保存・復元。

音声経路：

```text
Capture → SRC → Input Gain → AU Rack → Master GEQ → Master Gain → Limiter → Mute → Core Audio Output
```

## ビルド

Apple SiliconのMacとXcode Command Line Toolsが必要です。外部SDKやライブラリは不要です。

```sh
bash scripts/build.sh
open 'build/The Dutchman BOX-DAR.app'
```

生成されるアプリは開発用のad-hoc署名です。App Store配布用・公証済みのアプリではありません。

CMake 3.24以降がある場合：

```sh
cmake -S . -B build-cmake -DCMAKE_BUILD_TYPE=Release
cmake --build build-cmake
ctest --test-dir build-cmake --output-on-failure
```

CMakeでは`build-cmake/DesktopAudioRack.app`が生成されます。CMake経由のビルドは未検証です。

## 使い方

1. System Audioを選び、出力デバイスを指定してStart。
2. 初回はmacOSの音声収録権限を許可。
3. 起動直後だけ出力がミュートされているため「出力を有効にする」を押す。以後は手動のミュート状態を維持。
4. 空きスロットの「Add an effect」からメーカー別AUメニューを開いて選択。
5. EditorでプラグインGUIを表示。Input GainでAUへ送るレベルを調整。
6. プリセット名をクリックして選択、−／＋で前後へ切替。編集したプリセットは斜体＋`*`で表示。
7. 右下のMASTER EQから15バンドGEQを開く。閉じても処理・設定は維持。
8. StopでSystem Audioの取得を終了し、元音声の通常再生へ戻る。

ノブとEQフェーダーはドラッグで操作、Shiftで微調整、ダブルクリックで0 dB。EQはFlatで全バンドを戻せます。

INPUTメーターはInput Gainの前、各スロットのメーターはそのAUの後、OUTPUTはミュートを含む最終出力です。

## 現時点の制限

- AUv2 Stereo Effect・単一入出力バスのみ。AUv3、VST3、Instrument、MIDI、サイドチェインは未対応。
- アプリ単位のScreenCaptureKit取得では元音声をミュートしないため、二重再生しない経路が必要。
- 第三者AUはin-processで実行。プラグイン自体のクラッシュを隔離する機能は未実装。
- Rack変更・プリセット適用時は出力を短く休止する。キャプチャと元音声のミュートは継続。
- SRCは検証用の線形補間。高品質SRCへの置換と長時間の安定性確認は後続課題。
- Limiterは−1 dBFSのサンプルピーク方式。true-peak保証・lookaheadはなし。
- 編集判定はAU公開の読み書き可能パラメータが対象。独自の非公開状態は検出できない場合がある。
- 保存対象はAU Rack。内蔵Gain / GEQ・デバイス設定はまだ保存しない。
- 出力はチャンネル1/2。デバイスのレートとバッファサイズは読み取りのみ。
- Crossfeed / HRTFは後続の開発項目。

## テスト

```sh
bash scripts/test.sh
bash scripts/test-au.sh
bash scripts/test-au-ui.sh
bash scripts/test-controls.sh
bash scripts/test-drawing.sh
bash scripts/test-preset-browser.sh
bash scripts/test-main-ui.sh
bash scripts/test-effect-menu.sh
```

各スクリプトはASan/UBSan付きで実行します。AU・GUIのテストにはAudio Componentサービスに接続できるmacOSのログインセッションが必要です。音声キャプチャの権限と実音声の動作は実機で確認してください。

実機でMcDSP等のAU動作・元音声のミュート・プリセット読込を確認済み。自動テストはApple標準AUとテスト用プロセッサを中心に検証しています。

## 構成

- `src/AudioBridge.hpp` — 固定容量SPSCバッファ、SRC、処理順序
- `src/ProcessTap.*` — System Audioの取得・元音声ミュート
- `src/Output.*` — Core Audio HAL出力
- `src/plugins/` — AUホスト、GUI、プリセット、Rack保存復元
- `src/DSP.hpp` — Gain、15バンドGEQ、Limiter
- `src/Main.mm` / `Theme.*` / `RackControls.*` / `MeterView.*` — AppKit UI

変更履歴は[CHANGELOG.md](CHANGELOG.md)、開発中の詳細メモは[docs/DEVELOPMENT_HISTORY.md](docs/DEVELOPMENT_HISTORY.md)を参照してください。

メーカー製プラグイン・プリセット・商標の権利は各権利者に帰属します。このリポジトリには第三者プラグインやメーカーのプリセットデータを含めません。
