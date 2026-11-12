# 0.0.12 — 空きラックから追加・8段表示

上部のAU選択プルダウンとAdd Effectを削除し、Scan AU / Save AU Rack / Load AU Rackの1行へ整理しました。

空き枠の「+ Add an effect」をクリックするとメーカー別のAUメニューが開きます。選択するとエフェクトを追加し、メニューを閉じただけでは追加しません。新しいAUをインストールしたらScan AUで一覧を更新してください。従来どおりジャック中も操作できます。

基本表示を8段へ拡張。標準サイズでは8個すべて挿した場合も表示領域に収まるよう、カードの余白を調整しています。小さいウィンドウではラック内のスクロールで操作できます。最大インスタンス数は8個です。

検証：メーカー別メニューからのAU追加、8個上限、8段の表示領域への収まり、削除後の再追加、上部プルダウン不在とScan / Save / Load保持、プリセットブラウザーの回帰テストが通過。

---

# 0.0.11 — Rack First / Navy・Crimson・Amber

A案を実装しました。メイン左の約75％をラックへ割り当て、各AUを大きなフェイスプレートとして表示します。番号、広いプリセット欄、−／＋、Editor、Bypass、並べ替え、削除を各段へ集約。空き枠を含めて6段を基本表示し、最大8個まで追加できます。小さいウィンドウや8段の場合はラック内だけスクロールします。

右側はINPUT / OUTPUTの縦型ステレオメーターとGainノブ、Master Limiterのストリップです。下端のMASTER EQボタンまたは小さな応答カーブをクリックすると、15バンドGEQをフローティングパネルで開きます。閉じてもEQ処理・設定値は維持されます。

配色は青みの強いネイビー（#10264B）、深いクリムゾン（#B51F35）、アンバー（#FFAF24）。入力・出力メーターの安全域は緑です。

各AUカードの小型L/Rメーターはそのスロット直後の出力です。約200 ms周期でピークを表示します。右側INPUTは従来通りCapture直後、OUTPUTは全処理とミュート後。音声チェインはInput Gain → AU Rack → GEQ → Master Gain → Limiterのままです。

プリセットのチェック、編集状態の斜体＋*、ザッピング、Rack状態保存復元、フローティングエディタは継続対応。

検証：Apple標準AUのレンダー・プリセット、プリセットブラウザーとエディタの回帰試験、メインの占有率・サイズ変更・GEQパネル開閉、4スロットを入れた画面の描画を確認。

---

# 0.0.10 — プリセット表示・編集状態・ザッピング

各AUスロットを2段に整理し、下段に「− / プリセット名 / +」を表示します。名前をクリックすると従来のプリセットメニューを開きます。

- 読み込んだ項目にチェックマーク。Factory PresetとInstalled Presetsの両方に対応し、同名ファイルはパスで識別します。
- プラグインGUIからAU公開パラメータを変更すると、読み込み元の名前を斜体＋「*」で表示。エディタのタイトルにも反映。停止中も約200 ms間隔で更新します。
- 元の値へ戻せば「*」が消えます。プリセットを再読み込みしても編集状態はクリアされます。
- −／＋でメニュー順（Factory → Installed）に切り替え。端では循環します。未選択なら＋は先頭、−は末尾から開始。変更した値は次のプリセット読込で置き換わります。
- AU Rackの保存・復元にプリセット名・読み込み元と比較用パラメータを含めます。旧版のRackファイルも読み込めますが、名前情報がなければ未選択表示です。

編集判定はAUが読み書き可能として公開するパラメータが対象です。メーターなど読み取り専用値を除外し、音声スレッドでの状態シリアライズや比較は行いません。AU非公開の独自状態だけが変わる操作は検出できない場合があります。

メニューを開くか−／＋を初めて押した時に一覧を作り、以後はスロット単位でキャッシュします。アプリ起動中にプリセットファイルを追加した場合はそのAUスロットを追加し直すと一覧を更新できます。

回帰テスト：`bash scripts/test-preset-browser.sh`。同名ファイルのチェック識別、編集検出、元の値への復帰、複数インスタンスの独立、循環切替、並べ替え時の追従、名前・編集状態の保存復元をApple AUで検証しています。メーカーAU固有の編集通知・公開パラメータは実機確認対象です。

---

# 0.0.9 — フローティングGUI・メーカーPreset

Editorで開いたプラグインGUIはフローティングパネルとして、メインウィンドウより手前に残ります。メーターを見ながらメインのInput Gainノブを操作できます。他アプリへ切り替えたときは一時的に隠れます。

スロットの「Presets…」から以下を選べます。

- AUが公開するFactory Preset：名前を選ぶと適用。
- Installed Presets：`/Library/Audio/Presets`と`~/Library/Audio/Presets`内の、プラグイン識別子が一致する`.aupreset`を自動列挙。Artist Presetも対象。ファイルの場所はメニュー項目のツールチップで確認できます。
- Load .aupreset…：任意の標準AUプリセットファイルを選択。

このMacのMC404フォルダでは、対応する`.aupreset`を41個確認しました。メーカー独自形式やVST用`.vstpreset`はここでは読み込めません。AU公開のFactory Presetがなくても、Installed Presetsには対応ファイルが表示されます。

プリセット適用時はキャプチャを継続して処理出力だけを短く休止し、適用後に自動再開します。Input GainやMaster Gainは変更しません。AU Rack保存時には適用後のプラグイン状態を保存します。

検証：Apple AUのFactory Preset列挙・適用・適用後レンダー、`.aupreset`の読み込みと異なるプラグインのファイル拒否、フローティングパネルの生成と再表示がASan/UBSan付きテストで通過。MC404の実音声でのプリセット切替は実機確認待ちです。

---

# 0.0.8 — Input GainをAU Rackの前へ移動

信号順を Capture → SRC → **Input Gain → AU Rack → GEQ → Master Gain → Limiter** → Mute → Output に修正しました。Input Gainでプラグインへの送りレベルを変えられます。Input Bypassは送りゲインを0 dBへ戻し、Master Gainはプラグインへの入力には影響しません。Gain変更の平滑化とGUI配置は維持しています。

INPUTメーターは引き続きキャプチャ直後（Input Gainより前）、OUTPUTメーターは全処理とミュートの後です。Input Gainを変えた際はプラグイン側の入力メーターで送りレベルを確認できます。

回帰テストでは非線形のテストEffectを用い、44.1 / 48 / 96 kHzで送りゲイン、Input Bypass、Master Gainとの独立性を確認します。

---

# 0.0.7 — クラッシュ修正版

AU追加時に発生したクラッシュのレポートでは、メーター文字描画の属性辞書生成中に例外が発生していました。フォント取得失敗時の代替フォントと、nilの描画属性を辞書に入れない処理を追加しています。GEQ／ノブにも同じ対策を適用し、GUIの配置は維持しました。

回帰テスト：`bash scripts/test-drawing.sh`（Audio Componentサービスに接続できるmacOSログイン環境が必要）。フォント／色の欠落、無効な文字サイズ、20回のApple AU読み込み後のメーター・GEQ描画を検証します。

---

# 0.0.6 — コンパクトなメイン画面と専用GEQ

メイン画面を1160×780ポイントに整理。上段は左右独立メーター、中央左はAU Rack、中央右はInput / Master GainのノブとLimiter、下段は専用15バンドGEQです。メイン全体のスクロールはなく、AUが多い場合だけスロット一覧内をスクロールします。

GEQは±12 dBの目盛り、0 dBライン、小型フェーダー、周波数・ゲイン表示と設定応答カーブを描画します。カーブはFFTスペクトラムではなく、出力デバイスのレートを用いたEQ係数の定常応答です。設定変更時のDSP平滑化はカーブ表示とは別に作用します。

- GEQ：フェーダーを縦ドラッグ、ダブルクリックでそのバンドを0 dB。Shiftで微調整。Flatで全バンドを0 dB。
- Gain：ノブを上下ドラッグ。Shiftで微調整、ダブルクリックで0 dB。
- GEQはクリックしてバンド選択後、左右キーで選択、上下キーで0.5 dB調整。ノブも上下キーで操作できます。

信号順は Capture → SRC → AU Rack → Input Gain → GEQ → Master Gain → Master Limiter → Mute → Output に変更しました。Master Gainを下げるとEQの残響・フィルターの余韻も含めて減衰します。

DSP応答、EQ後のMaster Gainを確認する過渡応答テスト、ノブの値・操作通知・範囲、GEQ Flat、埋め込みAU Rackの回帰テストを追加・実施しています。

以下は旧版の変更履歴です。

---

# The Dutchman BOX/DAR — 0.0.5

今回の操作仕様は以下の通りです。下部の旧版説明よりこちらを優先してください。

- 自動ミュートはプロセス起動時の1回だけ。最初の解除後はStart/Stop、出力先変更、AU変更でも手動ミュート状態を維持します。Emergency Muteは引き続き使用できます。
- AU Rackをメイン画面に統合。追加／削除／順序変更はジャック中も可能です。変更中はCore Audio出力だけを同期休止し、キャプチャと元音声のミュートは継続します。変更後に自動再開します。これは無音ギャップなしの変更ではなく、短い休止を伴います。第三者AUの状態取得や削除が遅ければ休止も長くなります。
- AUのEditorボタンから純正GUIを直接開けます。別のRackウィンドウを開く必要はありません。
- 内蔵の1バンドParametric EQを15バンドMaster Graphic EQへ置換。25 / 40 / 63 / 100 / 160 / 250 / 400 / 630 Hz、1 / 1.6 / 2.5 / 4 / 6.3 / 10 / 16 kHz。±12 dB、Bypass、Flatリセット。ゲインを平滑化し、Master Gainの後・Limiter直前に挿入しています。
- メイン画面はサイズ変更とスクロールに対応。AUスロットが増えても下部のEQやメーターへアクセスできます。

信号順：Capture → SRC → AU Rack → Input Gain → Master Gain → 15-band Master EQ → Limiter → Mute → Output。

まず旧版を終了して新版を起動し、System Audio → Start → 初回だけ出力を有効にします。次に音を流したままAUのAdd／Remove／順序変更を試してください。EQは各縦フェーダーで操作し、Flatで全バンドを0 dBへ戻せます。

AU Rackの保存は従来通りAUの種類・順序・状態・Bypassが対象です。15バンドEQや内蔵Gainの保存はまだ含みません。VST3、Crossfeed、HRTFも後続の開発項目です。この版は今回の4項目を反映した使い勝手改善版です。

---

# 0.0.4 修正：System Audioの二重再生とAU画面

「System Audio」を選び直してStartすると、macOS 14.2以降ではCore Audio Process Tapを使用します。取得中だけ元音声をミュートし、自アプリの処理出力は除外します。Start後は処理出力も初期ミュートのため「出力を有効にする」を押してください。Emergency Muteは元音声をミュートしたまま処理出力を止めます。Stop／終了／開始失敗時はTapを破棄し、通常の直接再生に戻ります。OSの「システム音声の収録」許可が追加で求められる場合があります。

アプリ選択（ScreenCaptureKit）では元音声をミュートしません。自動ミュート対応は今回System Audioに限定しています。ハードウェア全体の音量やミュート設定は変更しません。

AUエディタはプラグインの推奨・実サイズで開き、サイズ変更通知に追従します。画面より大きい場合はウィンドウを画面内に収め、スクロールで全体にアクセスします。

既存DSPテストとApple標準AUエディタ生成テストは通過。Process Tapによる実際の音楽の元音声ミュートとMcDSP画面は実機確認待ちです。

参考：[Apple CATapMuteBehavior](https://developer.apple.com/documentation/coreaudio/catapmutebehavior)

---

# The Dutchman BOX/DAR — Milestone C

macOS 14以降 / Apple Silicon向け、ScreenCaptureKit → stereo FIFO / SRC → Core Audio HAL Output の検証用アプリです。C++20 / Objective-C++、外部ライブラリ不要。Input Gain / Parametric EQ / Master Gain / Limiterを実装。AUv2 Effectホストを追加しました。VST3・HRTFは未実装です。

## 起動

`build/The Dutchman BOX-DAR.app`をFinderで開いてください。開発用のad-hoc署名です。

1. 「アプリを選択…」でmacOS標準ピッカーから対象アプリを選ぶか、「System Audio」を選択。
2. macOSから求められた画面・システム音声収録権限を許可。必要ならシステム設定の「プライバシーとセキュリティ」で許可してアプリを再起動。
3. ステレオ出力デバイスを選択。出力チャンネルは1/2固定。
4. 再生元で音楽を再生し、Startを押してInputメーターを確認。
5. 経路と音量を確認して「出力を有効にする」を押す。起動・再開時は必ずミュート。
6. Emergency Muteで即座に無音化。Stopでキャプチャと出力を停止。

**元アプリの直接再生はこのアプリでは消しません。** 取り込み対象から自アプリの音は除外しますが、これは二重再生防止とは別です。たとえばmacOS通常出力を未接続のHDMI等の別経路にし、本アプリの出力をヘッドホン接続のオーディオインターフェースにするなど、直接音が耳に届かない経路で確認してください。通常出力先の音量変更はキャプチャへの影響も実機確認してください。本アプリはシステム既定出力を変更しません。

## ビルドとテスト

Command Line Toolsのみでビルド可能です。

```sh
bash scripts/build.sh
bash scripts/test.sh
```

CMake 3.24以降がある環境：

```sh
cmake -S . -B build-cmake -DCMAKE_BUILD_TYPE=Release
cmake --build build-cmake
ctest --test-dir build-cmake --output-on-failure
```

## Audio Units Rack（0.0.3）

1. 旧版を終了して新版を起動し、停止中に「Audio Units Rack…」を開きます。
2. Scanで登録済みAUv2 Effectを列挙し、プルダウンから選択してAdd。同一AUも別インスタンスとして追加できます（最大8個）。
3. 入力と出力を選択してStart。ミュートを解除し、RackのEditorからパラメータを操作します。Start時にはエディタを閉じるため、必要なら再度Editorを押してください。
4. 純正Cocoaエディタがあれば使用し、なければApple AUGenericViewを表示します（ウィンドウ名にGeneric Controlsと表示）。
5. Bypassは再生中も可能。初版はdryへの直接切替で、テール保持・レイテンシ補償はありません。切替時の音の不連続を避けたい場合は先にEmergency Muteを使ってください。
6. Stop後、↑／↓で順序を変更、Removeで削除できます。
7. Stop後、Save AU Rack…でAUの種類・順序・状態・Bypassをplist保存し、Load AU Rack…で復元できます。これはAU Rackのみの保存で、キャプチャ／出力デバイスや内蔵DSPの値は含みません。

信号順はCapture → SRC → AU Rack → 内蔵Input Gain / EQ / Master Gain / Limiter → Outputです。メーターのINPUTは全処理前、OUTPUTはミュートを含む全処理後です。

対象はAUv2のAudio Effect（aufx）、1入力バス／1出力バス、Float32 Stereo対応です。Instrument、MIDI、AUv3、サイドチェイン付き複数バスは対象外。Scan時には候補を列挙し、追加・Start時にStereo形式を検証します。追加時は48 kHz、Start時は出力デバイスのレートで再構成します。

失敗したスロットはERROR / dry表示となり、無加工で次段へ渡します。Startで再初期化を試みます。復元が失敗した場合は元のRackを維持します。クラッシュする第三者AUを隔離する機能はまだありません（in-process）。

Rackウィンドウのタイトルは有効スロットのReported Latency合計です。取得できない値はunknownと表示し、キャプチャ／出力やSRCの遅延は含みません。

### 検証

2026-11-12：Apple AUHipassを用いた実際のAudioUnitRender、カットオフ変更の周波数応答、Stereo左右独立、Bypass、ClassInfo保存・復元、44.1/48/96 kHz、複数インスタンス、ブロック分割、欠落プラグインのdry fallbackがASan/UBSan付きで通過。Apple AUHipassの純正Cocoaエディタ生成・再表示・破棄もASan/UBSan付きで通過。既存バッファ・DSP試験も通過。AUのテストはAudio Componentサービスへ接続できるGUIログイン環境が必要です。

```sh
bash scripts/test-au.sh
bash scripts/test-au-ui.sh
```

第三者AUの純正エディタ互換性、実音声の長時間再生、保存ファイルを介した手動往復は実機確認待ちです。

参考：[Apple Audio Unit Properties](https://developer.apple.com/documentation/audiotoolbox/general-audio-unit-properties)

## メーターとDSP（0.0.2）

INPUT / OUTPUTのL/Rバーはサンプルピーク表示です。入力はキャプチャ直後、出力はDSPとミュート適用後です。目盛りは−60〜0 dBFS、数値は現在のピーク表示、白線は1.5秒のPeak Holdです。0 dBFS以上で赤いClipインジケータが保持され、メーターをクリックすると解除できます。停止／ミュート後のバーは減衰表示するため、即座には消えません。ミュート自体は即時に作用します。

- INPUT GAIN：−24〜+12 dB。
- PARAMETRIC EQ：1バンドのピーキングEQ。周波数20 Hz〜20 kHz、Gain ±12 dB、Q 0.2〜8。低い出力レートでは周波数を安全な範囲へ内部制限。
- MASTER GAIN：−60〜+6 dB。
- LIMITER：−1 dBFSのサンプルピーク制限、左右連動。GR表示は現在のゲイン低減量。true-peak／lookahead方式ではありません。Bypass中や切替遷移中は制限を保証しません。

初期Gain / EQは0 dB、Limiterは有効です。各段のBypassはチェックを付けるとその処理を迂回します。Emergency MuteはBypassとは独立しています。設定保存はまだないため、アプリ再起動時は初期値へ戻ります。

EQ係数の参考：[W3C Audio EQ Cookbook](https://www.w3.org/TR/audio-eq-cookbook/)。

## 実装

- 標準SCContentSharingPickerによる単一アプリ選択、System Audio選択。
- 入力48 kHz / Float32 / Stereo。自プロセス音声を除外。
- 固定容量SPSCリングバッファ。出力コールバックはメモリ確保、ロック、ファイルI/Oをしない。
- デバイスの現在の公称レートを読み、簡易線形補間SRCで出力。占有量に応じ最大±0.5%補正し、クロック差による滞留を抑える。
- 2,048入力フレーム（約42.7 ms）を貯めて開始。8,192フレームを超える滞留は破棄して回復。Queue表示は総レイテンシではない。
- 入出力ピーク、under/overrun、無効形式・非有限値カウンター。メーター下限−120 dBFS。
- ミュート解除時の短いゲインランプ。Emergency Muteは即時。
- 出力先変更時は停止。Startで新デバイスへ再開。切断・レート変更は200 ms間隔で検知して停止。自動的な別出力への切替なし。

## 検証状況と制限

2026-11-12：この環境のCommand Line Toolsでarm64ビルド・ad-hoc署名成功。ASan/UBSan付きテストで起動ミュート、左右独立性、緊急ミュート、容量超過、NaN処理、44.1/48/96 kHzと+100 ppmのクロック差、underflow、並行読み書きストレスが通過。

GUIの起動は実行環境のLaunch Services接続エラー（-10822）で未確認。権限・実音声・標準ピッカーのアプリごとの音声範囲・外部デバイスは未検証。CMake自体が未導入のためCMake経由のビルドも未検証です。その後、ユーザーの実機動作確認によりMilestone Aは受け入れ済みです。Milestone Bもユーザーから画面と動作の確認を受け、Milestone Cへ進んでいます。

線形補間SRCは経路検証用です。高品質な帯域制限SRCへの置換、タイムスタンプに基づく欠落検知、長時間実機試験は後続課題。Limiterは出力段にあり、キャプチャ前に生じたクリップを修復しません。固定ステレオ出力、読み取り専用のレート・バッファサイズ表示、プリセットなし。アプリ側の停止処理は非同期完了後に次のStartを許可します。

## Milestone A 実機チェックリスト

- [ ] 権限の未許可→許可、および拒否時のエラー表示
- [ ] Music / Safari / Chromeのアプリ単位の入力メーターと左右の音
- [ ] System Audioの取り込み、自アプリ除外による循環防止
- [ ] 直接音と処理経路の二重再生がない構成の確認
- [ ] Start/Stopの反復、ミュート状態での再開
- [ ] 出力デバイス切替・抜き差し・公称レート変更で安全に停止
- [ ] 44.1 / 48 / 96 kHzデバイスで音程とチャンネル1/2が正しい
- [ ] 2時間以上の再生でQueueが増加し続けない、dropout・メモリ増加がない
- [ ] 音源停止・再開、スリープ復帰、共有停止時の動作

ScreenCaptureKit API参考： https://developer.apple.com/documentation/screencapturekit


## Milestone B 確認手順

旧アプリを終了し、新名称のアプリを起動してください。既存版のアプリファイルは残しています。

1. Start → 入力メーターだけが動き、ミュート解除後に出力メーターも動くこと。
2. Input Gainを−12 dBに下げると入力メーターは変わらず、出力レベルが下がること。
3. EQを1 kHz / +6 dBに設定して音の変化を確認。Bypassで戻ること。
4. Master Gainを下げて出力だけが下がること。
5. Limiterが有効な状態で信号レベルを上げるとGRが増え、出力ピークが−1 dBFS付近以下になること。
6. Emergency Mute、Stop、出力先切替が引き続き安全に作用すること。

変更一覧は[CHANGELOG.md](CHANGELOG.md)を参照してください。
