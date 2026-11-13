# The Dutchman BOX/DAR

macOSで再生している音声を、AU/VST3エフェクトへ通して聴くためのスタンドアロン・オーディオラックです。

現在のバージョン：**0.0.29**（開発版）

## 動作環境

- Apple Silicon搭載Mac、macOS 14以降
- System Audioの元音声ミュートにはmacOS 14.2以降が必要
- ビルドにはXcode Command Line ToolsとVST3 SDKが必要

特定のオーディオインターフェースを前提としません。機器・ドライバー・プラグインの組み合わせによって動作が異なります。

## 主な機能

- Core Audio Process Tapによるシステム音声の取得と、取得元の直接再生のミュート
- ScreenCaptureKitによるアプリ単位の音声取得
- AUv2/VST3ステレオEffectを使用できる固定8スロット
- プラグイン名からの差し替え、ドラッグによるスロット交換、空き位置を保持した保存
- メーカーGUIのフローティング表示
- AUのFactory Preset・`.aupreset`読込、選択状態・編集状態の表示、前後切替
- Input Gain、15バンドMaster GEQ、Master Gain、Limiter、Emergency Mute
- ヘッドホン向けCrossfeedと音場操作パネル
- VST3一覧のキャッシュと起動時の差分スキャン
- アプリメニューのAbout画面、Audio Engine Diagnostics

## ビルド

リポジトリのルートで実行します。SDKの取得時はネットワーク接続が必要です。

```sh
bash scripts/setup-vst3.sh
bash scripts/build.sh
open 'build/The Dutchman BOX-DAR.app'
```

固定版のVST3 SDKを`build/`へ取得します。SDKのライセンス通知はアプリへ同梱されます。生成アプリは開発用のad-hoc署名で、公証済み配布物ではありません。

CMake 3.24以降を利用する場合も、先にSDKの取得が必要です。

```sh
cmake -S . -B build-cmake -DCMAKE_BUILD_TYPE=Release
cmake --build build-cmake
ctest --test-dir build-cmake --output-on-failure
```

CMake経由のビルドは未検証です。上記のシェルスクリプトによるビルドを確認対象としています。

## 基本操作

1. macOSの通常出力を再生元の出力先に設定します。System Audioの取得対象は、そのデバイスの先頭ストリームのチャンネル1/2です。
2. BOXでSystem Audioと処理後の出力デバイスを選び、Startを押します。初回はmacOSの収録権限を許可してください。
3. 起動直後の出力ミュートを解除します。その後のStart/Stopでは手動のミュート状態を維持します。
4. 空き枠のAdd an effectからプラグインを選びます。挿入済みの名前をクリックすると、その枠のプラグインを差し替えられます。
5. 番号またはプラグイン名をドラッグして移動先へドロップします。空き枠なら移動、使用中なら交換します。削除しても後ろの枠は詰めません。
6. EditorでメーカーGUIを開きます。VST3のプリセットはメーカーGUI内で選択してください。
7. MASTER EQとSPATIALは、それぞれ独立したパネルで編集できます。
8. Stopで取得を終了します。System Audioでは元音声の通常再生へ戻ります。

ゲインノブはドラッグ・マウスホイールに対応し、Shiftで微調整できます。ゲインノブとEQフェーダーはダブルクリックで0 dBへ戻せます。

アプリ単位の取得では元音声をミュートしません。二重再生しない出力経路を用意してください。BOXはmacOSの既定出力を自動変更しません。

## 保存とスキャン

**Save the Rack / Load the Rack**で、プラグインの状態・順序・Bypass・空き位置に加え、Input/Master Gain、GEQ、Spatial、Limiter Bypassを保存・復元できます。現行形式はv4で、旧v1〜v3も読み込めます。旧ファイルに含まれない内蔵設定は現在値を維持します。

出力デバイス、Start/Stop、Emergency Mute状態は保存対象外です。設定の保存は明示的なファイル操作で、起動時のラック自動復元ではありません。

VST3は起動直後にキャッシュから候補を表示し、追加・更新・削除をバックグラウンドで確認します。**Scan VST3**はキャッシュを無視した全件再スキャンです。認証変更などで候補が表示されない場合にも利用できます。スキャン候補への掲載は互換性の保証ではなく、挿入時に形式を検証します。

## 音声経路

```text
Capture → Clock/Rate Adapter → Input Gain → AU/VST3 Rack
        → Crossfeed → Master GEQ → Master Gain → Limiter → Mute/Fade → Core Audio Output
```

出力デバイスのサンプルレートに追従します。通常のSystem Audio経路ではクロック同期を証明できないため、同一サンプルレートでもASRCを使用します。Directは同期が証明された条件の経路であり、単にレートが一致しただけでは選択しません。Legacy Linearはアプリメニューから次回Startに適用できる比較・フォールバック経路です。

INPUTメーターはInput Gainの前、スロットメーターは各エフェクトの後、OUTPUTはミュートを含む最終出力です。

全プラグインのBypassはエンジン全体の無処理を意味しません。GEQのFlatとBypassは別で、Limiterは初期状態で有効です。経路比較時は各状態とASRCの実動作をDiagnosticsで確認してください。

## 現在の制限

- AUv2/VST3のステレオEffectが対象です。AUv3、VST2、Instrument、MIDI、Intel専用プラグインのブリッジは未対応です。
- VST3の補助音声バスは無効化します。外部サイドチェインのルーティングと完全なライブ入出力再構成は未対応です。
- 処理とGUIは同一プロセスです。スキャンは別プロセスですが、稼働中のプラグインのクラッシュは隔離しません。
- ラック変更・状態読込時は出力を短く休止します。キャプチャは継続します。
- Limiterは−1 dBFSのサンプルピーク方式です。True Peakやlookaheadの保証はありません。
- SpatialはCrossfeedです。HRTF、部屋の反射、ヘッドトラッキングは未実装です。
- 通常再生とBOX経由の出力がエンドツーエンドでbit-exactであることは確認できていません。
- コールバック空白の発生原因は未特定です。0.0.29では復旧時に古い制御状態が残る問題を修正していますが、すべての音切れの解消を保証しません。

## テストと技術資料

```sh
bash scripts/test.sh
bash scripts/test-rate-adapter.sh
bash scripts/test-recovery-reset.sh
bash scripts/test-au.sh
bash scripts/test-effect-menu.sh
bash scripts/test-main-ui.sh
bash scripts/test-vst3.sh
bash scripts/test-vst3-ui.sh
bash scripts/test-vst3-catalog.sh
```

テストには実行環境・macOSサービスへの接続が必要なものがあります。ネイティブ音声・GUI試験はmacOSのログインセッションで実行してください。サニタイザーの適用範囲は各スクリプトを参照してください。合成入力による試験は、実デバイスでの長時間安定性や全プラグインの互換性を保証しません。

- [変更履歴](CHANGELOG.md)
- [開発概要](docs/DEVELOPMENT_HISTORY.md)
- [Clock/Rate Adapterの測定](docs/engine-phase1/REPORT.md)
- [復旧処理の調査](docs/recovery-investigation/REPORT.md)
- [VST3対応範囲](docs/vst3/PHASE1.md)
- [透明性の調査](docs/transparency/REPORT.md)
- [公開文書の編集方針](docs/PUBLICATION.md)

第三者プラグイン・プリセット・商標の権利は各権利者に帰属します。第三者プラグインやメーカーのプリセットデータは同梱しません。
