# The Dutchman BOX/DAR

macOSで再生している音声を、AU/VST3エフェクトへ通して聴くためのスタンドアロン・オーディオラックです。

現在のバージョン：**1.0.3**

## 動作環境

- Apple Silicon搭載Mac、macOS 14以降
- System Audio（Core Audio Process Tap）はmacOS 14.2以降。macOS 14.0〜14.1では標準ピッカーによるアプリ音声の取得を利用できます。
- ビルドにはXcode Command Line ToolsとVST3 SDKが必要

特定のオーディオインターフェースを前提としません。機器・ドライバー・プラグインの組み合わせによって動作が異なります。

## 主な機能

- Core Audio Process Tapによるシステム音声の取得と、取得元の直接再生のミュート
- macOS 14.2以降のApplication Tapによるアプリ単位の音声取得と原音ミュート
- AUv2/VST3ステレオEffectを使用できる固定8スロット
- プラグイン名からの差し替え、ドラッグによるスロット交換、空き位置を保持した保存
- メーカーGUIのフローティング表示
- AUのFactory Preset・`.aupreset`読込、選択状態・編集状態の表示、前後切替
- Input Gain、15バンドMaster GEQ、Master Gain、Limiter、Emergency Mute
- ヘッドホン向けCrossfeed・HRTFと音場操作パネル
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

### アプリを指定して聴く

macOS 14.2以降では、対象アプリで再生を始めてからBOXの **Application…** でそのアプリを選び、Startを押します。通常出力デバイスの先頭ストリームのチャンネル1/2から、対象プロセスの音声を元のレベルで取り込みます。Start中は取得対象の原音がミュートされ、Stopで直接再生に戻ります。開始時に有効な入力ブロックが届かない場合は数秒で停止します。

Safariは **Application… → Safari → 音声プロセス名** の順に選びます。システムが表示する「Safari Graphics and Media」など、Safariに対応する項目を選択してください。WebKitの音声サービスは他のアプリにも使われるため、表示名を確認して明示的に選びます。

対象はアプリ本体と、そのアプリに属する音声用の補助プロセスです。Core Audioが出力中と報告する音声クライアントを選び、再生中の追加・入れ替えを監視してTapの対象を更新します。ブラウザはアプリ単位で取り込むため、タブ単位の選択には対応していません。

ChromeなどからインストールしたPWAを選んだ場合は、音声を担当する親ブラウザ全体を取り込み、原音もブラウザ全体でミュートします。親ブラウザを一意に特定できない場合は開始しません。対象アプリや親ブラウザを開き直した場合は、選び直してStartしてください。

macOS 14.0〜14.1の標準ピッカー経由では原音が鳴り続けます。この経路で処理後の音だけを聴くには、原音が混ざらない出力経路が必要です。BOXはmacOSの既定出力を自動変更しません。

## 保存とスキャン

**Save the Rack / Load the Rack**で、プラグインの状態・順序・Bypass・空き位置に加え、Input/Master Gain、GEQ、Spatial、Limiter Bypassを保存・復元できます。現行形式はv4で、旧v1〜v3も読み込めます。旧ファイルに含まれない内蔵設定は現在値を維持します。

VST3の保存には、停止中やBypass中に行った未反映のパラメータ編集も含まれます。復元時はスキャン済みのインストール候補をクラスIDで照合します。候補が見つからない場合や一意に特定できない場合は、現在のラックを維持します。

出力デバイス、Start/Stop、Emergency Mute状態は保存対象外です。設定の保存は明示的なファイル操作で、起動時のラック自動復元ではありません。

VST3は起動直後にキャッシュから候補を表示し、追加・更新・削除をバックグラウンドで確認します。**Scan VST3**はキャッシュを無視した全件再スキャンです。認証変更などで候補が表示されない場合にも利用できます。スキャン候補への掲載は互換性の保証ではなく、挿入時に形式を検証します。

## 音声経路

```text
Capture → Clock/Rate Adapter → Input Gain → AU/VST3 Rack
        → Spatial → Master GEQ → Master Gain → Limiter → Mute/Fade → Core Audio Output
```

出力デバイスのサンプルレートに追従します。通常のSystem Audio経路ではクロック同期を証明できないため、同一サンプルレートでもASRCを使用します。Directは同期が証明された条件の経路であり、単にレートが一致しただけでは選択しません。Legacy Linearはアプリメニューから次回Startに適用できる比較・フォールバック経路です。

INPUTメーターはInput Gainの前、スロットメーターは各エフェクトの後、OUTPUTはミュートを含む最終出力です。

全プラグインのBypassはエンジン全体の無処理を意味しません。GEQのFlatとBypassは別で、Limiterは初期状態で有効です。経路比較時は各状態とASRCの実動作をDiagnosticsで確認してください。

## 現在の制限

- AUv2/VST3のステレオEffectが対象です。AUv3、VST2、Instrument、MIDI、Intel専用プラグインのブリッジは未対応です。
- VST3の補助音声バスは無効化します。外部サイドチェインのルーティングと完全なライブ入出力再構成は未対応です。
- 処理とGUIは同一プロセスです。スキャンは別プロセスですが、稼働中のプラグインのクラッシュは隔離しません。
- 再生中のラック編集・状態保存・復元では、出力を一時停止してから操作します。キャプチャは継続します。出力を停止できない場合は操作を中止します。
- Limiterは−1 dBFSのサンプルピーク方式です。True Peakやlookaheadの保証はありません。
- SpatialはOFF、Crossfeed、HRTFから選択できます。HRTFではリンクした左右の仮想スピーカーをドラッグして水平角（±10〜75°）を調整します。どちらのモードでもスピーカー上のホイールで角度を調整できます。HRTFの初期角度は±60°です。距離・量はCrossfeed専用です。部屋の反射、ヘッドトラッキング、LCR分離は未実装です。
- 通常再生とBOX経由の出力がエンドツーエンドでbit-exactであることは確認できていません。
- ASRCは入力不足を確定する直前に、直近に到着した入力を再確認します。入力が実際に不足した場合は再プリミングします。実機で観測されたコールバック空白については、復旧処理の調査を参照してください。

## テストと技術資料

```sh
bash scripts/test.sh
bash scripts/test-rate-adapter.sh
bash scripts/test-recovery-reset.sh
bash scripts/test-recovery-diagnostics.sh
bash scripts/test-recovery-parity.sh
bash scripts/test-hrtf.sh
bash scripts/test-spatial-ui.sh
bash scripts/test-au.sh
bash scripts/test-effect-menu.sh
bash scripts/test-main-ui.sh
bash scripts/test-vst3.sh
bash scripts/test-vst3-ui.sh
bash scripts/test-vst3-catalog.sh
```

波形回帰テストは、決定論的な入力で0.0.29と比較します。混在ラックの試験（`test-vst3-ui.sh`）は、直前の`test-vst3.sh`で生成するテスト用プラグインを使います。

Diagnosticsの画面やログを共有する際は、デバイス名・識別子など環境を特定できる項目を伏せてください。

テストには実行環境・macOSサービスへの接続が必要なものがあります。ネイティブ音声・GUI試験はmacOSのログインセッションで実行してください。サニタイザーの適用範囲は各スクリプトを参照してください。合成入力による試験は、実デバイスでの長時間安定性や全プラグインの互換性を保証しません。

- [変更履歴](CHANGELOG.md)
- [開発概要](docs/DEVELOPMENT_HISTORY.md)
- [Clock/Rate Adapterの測定](docs/engine-phase1/REPORT.md)
- [復旧処理の調査](docs/recovery-investigation/REPORT.md)
- [HRTFの設計と検証](docs/spatial/HRTF.md)
- [VST3対応範囲](docs/vst3/PHASE1.md)
- [透明性の調査](docs/transparency/REPORT.md)
- [公開文書の編集方針](docs/PUBLICATION.md)

第三者プラグイン・プリセット・商標の権利は各権利者に帰属します。第三者プラグインやメーカーのプリセットデータは同梱しません。
