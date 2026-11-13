# Changelog

各項目は、そのバージョンでの変更です。現在の仕様はREADMEを参照してください。

## 0.0.29 — Recovery state reset
- 過剰backlog位置変更後に古いfillを制御へ渡す問題を修正。
- 再priming時に古いPI/平滑化/slew履歴をリセット。正常時の係数・SRC/DSP処理は維持。
- 効果音時のCapture/Output callback空白の発生原因は未特定。実機確認は継続。

## 0.0.28 — Cached VST3 discovery
- 起動時にVST3キャッシュを即時使用し、追加/更新/削除だけバックグラウンドで確認。
- 変更なし/失敗済みバンドルを再ロードせず、手動Scanは全件再スキャン。
- スキャン中もラック編集可能。スキャンボタンの二重実行防止。表示中メニューは候補IDを保持し、差分更新で別のプラグインを選ばないよう対応。
- キャッシュ破損復旧、ネストしたバイナリ変更、追加/削除、負キャッシュ、強制再読込を検証。音声スレッドにIO追加なし。

## 0.0.27 — Fixed insert slots
- 空き枠へ移動、使用中の枠とは交換。削除時に詰めず、Addはクリックした枠へ挿入。
- 空きを含むv4保存/復元。v1〜v3互換。音声処理・メーター・GUI更新は空き枠をスキップ。
- 空き位置追加/交換/削除、native drop、保存往復、旧形式、空き枠の音声通過を検証。

## 0.0.26 — Rack interaction / About
- 挿入済みのプラグイン名をクリックしてAU/VST3を差し替え。8枠使用中でも可能。初期化失敗は元を保持し、Bypassを継承。
- 番号・プラグイン名からネイティブDrag & Dropで並べ替え。挿入線、同一ラック/世代検証、編集中の拒否、ドラッグ元の寿命保持を追加。
- アプリケーションメニューへAboutを追加。Bundleのversion/buildを表示。
- 差し替え・DnD受け渡し・旧payload拒否・設定保存回帰・Aboutメニューを検証。SRC/DSP処理変更なし。

## 0.0.25 — VST3 auxiliary bus compatibility
- 補助サイドチェイン入力を理由にステレオ初期化を拒否していた問題を修正。
- メイン入出力はFloat32 Stereoを維持し、補助バスは宣言されたlayoutを保持して明示的に無効化。全バス分の固定メタデータ/ポインタ配列を事前確保。
- エラー段階名がcontroller.initializeのまま残る表示を修正。
- 第三者VST3での再現条件に対し、修正後の処理・GUIを確認。補助入力付きfixtureでheadroom/bypass/state/rate/heap回帰を検証。
- 外部サイドチェインのルーティングは未提供。SRC/AU/既存DSPアルゴリズムは変更なし。

## 0.0.24 — Full rack settings
- Save/Load the RackにInput/Output Gain、GEQ 15バンド/Bypass、Spatial enabled/angle/distance/amount、Limiter Bypassを追加（schema v3）。
- 復元後にノブ・チェックボックス・EQ/音場表示も同期。Start/Stop、出力デバイス、Emergency Muteは維持。
- v1/v2互換。旧形式では未保存設定を維持。不正設定・プラグイン復元失敗は全体を変更せず中止。
- AU/VST3混在ファイル往復、旧形式、不正値/欠損、UI同期を検証。SRC/DSP方式は変更なし。

## 0.0.23 — Rack controls fix
- 再生中の定期controls更新でVST3プリセット欄が有効/無効を往復する点滅を修正。プリセット欄と±ボタンの可否を一箇所で管理。
- 同じプリセット表示を毎回再設定せず、変更時だけ更新。
- Save the Rack / Load the Rackへ名称変更。保存内容は従来どおりAU/VST3ラックのみ（Gain/GEQ/Spatialは未保存）。

## 0.0.22 — VST3 first milestone
- 固定版MIT VST3 SDKを導入。別プロセスでEffectをスキャンし、arm64/Float32/stereoで挿入時に検証。
- AU/VST3共通のRackEffectへ所有・dispatchを分離。既存AU処理本体は変更なし。
- VST3の音声処理、GUIパラメータ転送、純正NSViewフロート表示、Bypass・並べ替え・削除・状態保存復元。
- VST3プリセットはメーカーGUI内で選択。Intel/Rosetta、Instrument、追加音声バス、完全なlive IO再構成は未対応。
- 決定的なテスト用VST3、混在ラック回帰、実プラグインのGUI/処理スモークテストを追加。SRC/DSPアルゴリズム変更なし。

## 0.0.21 — Recovery diagnostics
- SRC/PI/DSP/音声の挙動は変えず、先読み不足・再priming・過剰backlogのイベント観測を追加。
- Capture/Outputの到着間隔、timestamp連続性、PI内訳、固定/最新write位置、ゼロ入力補充を表示。
- 固定write snapshotとqueue transient後のratio応答遅延を再現。過去のイベントの原因は未確定。
- 0.0.20との4モード・450万サンプルの音声byte一致を確認。

## 0.0.20
- ネイビーの3段ラックとCrimson/Amberストライプをモチーフにしたアプリアイコンを追加。
- 16〜1024pxのmacOS .icnsを生成し、shell/CMake両方のbundleへ組み込み。
- Audio Engineは0.0.19から変更なし（Auto / ASRC既定）。

## 0.0.19
- 再生試験の結果を踏まえ、起動時の既定をAuto Clock/Rate Adapterへ変更。現在のTap経路ではASRC。
- Legacyは次回Startに適用する手動fallbackとして維持。SRC・AU・DSPの演算内容は変更なし。

## 0.0.18
- 起動後半でQuitのみのメニューに上書きする処理を削除し、DiagnosticsとLegacy選択を表示。
- 起動完了後の実際のメニュー経由で、診断表示・ショートカット設定・Legacy切替を回帰検証。

## 0.0.17
- Input/Master Gainノブへマウスホイール操作を追加。通常0.5 dB/step、Shiftで1/10の微調整。
- トラックパッドの高精度スクロールは低感度、慣性スクロールは適用しない。
- Phase 1候補のLegacy既定・音声エンジンは変更なし。

## 0.0.16 — Phase 1 candidate
- Baseline b6b4c41を保持し、Legacy byte parity、Direct bit exact、Fixed/Async sinc、clock diagnosticsを追加。
- Apple Mastering/MaxとのWAV/CSV比較とASRC残差スペクトル、callback分布計測を追加。
- 自前sincは測定上CPU負荷で劣るため既定化を見送り。Legacy既定、新Adapterは明示的opt-in。
- AU Host / GEQ / Crossfeed / Limiterの実装は変更なし。詳細はdocs/engine-phase1/REPORT.md。

## 0.0.15
- Input Gain / Master GainのBypassをUI・DSPから削除。ノブの値を常に適用。

## 0.0.14
- System Audioを通常出力デバイスの先頭ストリームch 1/2の非ミックスダウンTapへ変更。多チャンネル機器のステレオミックスダウン減衰を避ける。
- 多チャンネルのインターリーブ／分離バッファから先頭ステレオペアを無補正で抽出。
- macOS通常出力変更時に停止して取り込み先の再接続を促す。
- 2/4/8/16chのレベル保持と無効バッファのテストを追加。実デバイスでのレベル差は別途検証対象。

## 0.0.13 — Spatial / Crossfeed

- メインからワンクリックで開くSpatialフローティングパネル。
- 透視投影グリッド上のスピーカー操作で角度・距離、中央リングのドラッグでAmountを変更。
- 固定容量バッファのCrossfeedをAU Rack後・Master GEQ前に挿入。パラメータとBypassを平滑化。
- HRTF未実装を明示。保存はAU Rackに限定した従来仕様を維持。
- 複数レートのDSP特性、操作座標変換とウィンドウ開閉を検証。

## 0.0.12 — Slot-local effect selection

- 上部のAUプルダウンとAdd Effectを廃止。Scan / Save / Loadを1行へ集約。
- 空きラックのAdd an effectからメーカー別AUメニューを開き、選択時に追加。
- 8段を基本表示し、標準サイズで8個すべて入れた状態でも収まるカード高へ調整。
- 追加・上限・削除後の再追加・表示領域とプリセット操作を回帰検証。

## 0.0.11 — Rack First

- 左約75%の大型ラックと右のマスターストリップへ再配置。
- Navy / Crimson / Amberの共通テーマ、専用ボタンとラックフェイスプレート。
- 各スロットの出力メーター、広いプリセット欄、番号と選択ハイライト。
- INPUT / OUTPUTを縦型メーターへ変更。
- Master EQをミニカーブから開くフローティングパネルへ移動。
- 可変サイズのメイン画面、Rack・GEQ開閉の回帰試験。

## 0.0.10 — Preset browser state

- スロットごとのプリセット名、メニューのチェック、編集状態の斜体＋*表示。
- AU公開の読み書き可能パラメータをロード直後の値と比較。メーターなど読み取り専用値は除外。
- −／＋によるメニュー順の循環切替。
- インスタンス自身にプリセット情報を保持し、並べ替え・AU Rack保存復元で維持。
- プリセット表示・編集判定・保存往復を対象にした回帰テストを追加。

## 0.0.9 — Floating editor / AU presets

- プラグインエディタをNSFloatingWindowLevelのNSPanelへ変更。
- AU FactoryPresetsを列挙し、PresentPresetで適用。
- インストール済み.aupresetを部品識別子で照合して自動列挙。ファイル指定による読み込みも追加。
- プリセット適用中は出力のみ休止し、ミュート状態を維持して再開。
- Factory Preset適用、標準ファイル復元、誤った部品の拒否とフローティングパネルをテスト。

## 0.0.8 — Pre-AU Input Gain

- Input GainをAU Rackの後段から前段へ移動。
- 音声エンジンがInput GainとMaster処理を別々に呼び、間にAU Rackを挿入する構成へ変更。
- 非線形テストEffectでゲインの位置を識別し、44.1 / 48 / 96 kHzで送りレベル・Bypass・Master Gainからの独立性を検証。

## 0.0.7 — メーター文字描画のクラッシュ修正

- 0.0.6のクラッシュレポートはDARMeterViewの文字属性辞書生成中の例外を示していた。欠けた属性がフォント・色のどちらかはログから判別できない。
- メーターとGEQ／ノブの文字描画を共通化し、取得できなかったフォントや色を辞書へ入れない処理へ変更。フォントはmonospaced → system → fixed-pitchの順にフォールバック。
- 非有限・非正の文字サイズを正規化。
- nilのフォント／色、全フォント取得失敗、AU追加後の再描画を確認する回帰テストを追加。
- GUIの配置・音声チェインは変更なし。

## 0.0.6 — 専用GEQ UI・画面の再配置

- 15バンドEQを専用描画のフェーダー、目盛り、0 dBライン、定常応答カーブへ変更。
- Gainをノブに変更。Shift微調整、ダブルクリック0 dB、キーボード操作。
- Master GainをGEQ後、Limiter直前へ移動。過渡応答で配置を検証。
- メイン画面を1160×780ポイントの左右配置に変更。全体スクロールを廃止し、AU一覧のみ内部スクロール。

## 0.0.5 — メイン画面統合・ライブRack編集

- ミュート状態を起動後のStart/Stopや出力切替で維持。
- キャプチャ継続中のAU追加・削除・順序変更・保存復元。共有Rackへ変更を加える間はAudioOutputUnitStopで出力コールバックを同期停止し、完了後に再開。
- Rackをメインウィンドウに埋め込み。純正GUIはEditorから直接表示。
- 15バンドMaster Graphic EQへ置換、Limiter直前に配置。
- メイン画面のスクロール・サイズ変更対応。

## 0.0.3 — Milestone C / Audio Units

2026-11-12

- AUv2 Stereo Effectの列挙、追加、最大8インスタンス、Bypass、順序変更、削除。
- 純正CocoaエディタとAUGenericView fallback。
- AU RackのClassInfoを含むplist保存／復元。復元失敗時は元のRackを維持。
- Reported Latencyとスロットエラー表示。形式不一致・render失敗はdryで迂回。
- 固定バッファによるブロック処理、単調増加するsample time、出力レート変更時の再構成。
- 追加・削除・順序変更・保存復元は停止中のみ許可。Editor／Bypassは再生中も操作可。
- Apple標準AUのレンダー・状態往復を検証。

AUv3、サイドチェイン、クラッシュ隔離、遅延補償、完全Rack Presetは未対応。

## 0.0.2 — The Dutchman BOX/DAR / Milestone B

2026-11-12

- 初期のキャプチャ・出力経路を確認。
- アプリ表示名をThe Dutchman BOX/DARへ変更。ファイル名はスラッシュを避けThe Dutchman BOX-DAR.app。既存の権限設定との連続性のためbundle identifierと実行ファイル名は維持。
- 暗色のラックUI、入力／出力L/Rメーター（約30 fps）、−60〜0 dBFSスケール、1.5秒ピークホールド、クリックで解除するClip表示。バーは24 dB/sで減衰。
- Input Gain（−24〜+12 dB）→1バンドParametric EQ（20 Hz〜20 kHz、±12 dB、Q 0.2〜8）→Master Gain（−60〜+6 dB）→Limiter（−1 dBFS、左右連動、80 ms release）。各段Bypass可能。
- Gain／Bypassの遷移を平滑化。EQ設定もブロック単位で平滑化。
- 出力メーターはミュート後、入力メーターはDSP前。LimiterのGain Reductionを表示。
- ミュート解除後の状態表示をLIVEへ変更。
- DSP追加後もASan/UBSan付きバッファ試験が通過。EQ応答、複数レート、左右独立、Limiter ceiling、左右連動、Bypass、メーター集計の試験を追加して通過。

制限：Limiterはlookaheadなしのサンプルピーク方式で、true-peak保証はありません。Bypass中および切替クロスフェード中は上限保証対象外です。高品質SRC、Crossfeed、AU/VST3、HRTF、保存機能は後続段階。GUIと実音声の確認範囲は当時の検証条件に依存します。
