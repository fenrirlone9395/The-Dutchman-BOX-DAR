## 0.0.15
- Input Gain / Master GainのBypassをUI・DSPから削除。ノブの値を常に適用。

## 0.0.14
- System Audioを通常出力デバイスの先頭ストリームch 1/2の非ミックスダウンTapへ変更。多チャンネル機器のステレオミックスダウン減衰を避ける。
- 多チャンネルのインターリーブ／分離バッファから先頭ステレオペアを無補正で抽出。
- macOS通常出力変更時に停止して取り込み先の再接続を促す。
- 2/4/8/16chのレベル保持と無効バッファのテストを追加。AudioFuseでの聴感差は実機確認待ち。

# 0.0.13 — Spatial / Crossfeed

- メインからワンクリックで開くSpatialフローティングパネル。
- 透視投影グリッド上のスピーカー操作で角度・距離、中央リングのドラッグでAmountを変更。
- 固定容量バッファのCrossfeedをAU Rack後・Master GEQ前に挿入。パラメータとBypassを平滑化。
- HRTF未実装を明示。保存はAU Rackに限定した従来仕様を維持。
- 複数レートのDSP特性、操作座標変換とウィンドウ開閉を検証。

# 0.0.12 — Slot-local effect selection

- 上部のAUプルダウンとAdd Effectを廃止。Scan / Save / Loadを1行へ集約。
- 空きラックのAdd an effectからメーカー別AUメニューを開き、選択時に追加。
- 8段を基本表示し、標準サイズで8個すべて入れた状態でも収まるカード高へ調整。
- 追加・上限・削除後の再追加・表示領域とプリセット操作を回帰検証。

# 0.0.11 — Rack First

- 左約75%の大型ラックと右のマスターストリップへ再配置。
- Navy / Crimson / Amberの共通テーマ、専用ボタンとラックフェイスプレート。
- 各スロットの出力メーター、広いプリセット欄、番号と選択ハイライト。
- INPUT / OUTPUTを縦型メーターへ変更。
- Master EQをミニカーブから開くフローティングパネルへ移動。
- 可変サイズのメイン画面、Rack・GEQ開閉の回帰試験。

# 0.0.10 — Preset browser state

- スロットごとのプリセット名、メニューのチェック、編集状態の斜体＋*表示。
- AU公開の読み書き可能パラメータをロード直後の値と比較。メーターなど読み取り専用値は除外。
- −／＋によるメニュー順の循環切替。
- インスタンス自身にプリセット情報を保持し、並べ替え・AU Rack保存復元で維持。
- プリセット表示・編集判定・保存往復を対象にした回帰テストを追加。

# 0.0.9 — Floating editor / AU presets

- プラグインエディタをNSFloatingWindowLevelのNSPanelへ変更。
- AU FactoryPresetsを列挙し、PresentPresetで適用。
- インストール済み.aupresetを部品識別子で照合して自動列挙。ファイル指定による読み込みも追加。
- プリセット適用中は出力のみ休止し、ミュート状態を維持して再開。
- Factory Preset適用、標準ファイル復元、誤った部品の拒否とフローティングパネルをテスト。

# 0.0.8 — Pre-AU Input Gain

- Input GainをAU Rackの後段から前段へ移動。
- 音声エンジンがInput GainとMaster処理を別々に呼び、間にAU Rackを挿入する構成へ変更。
- 非線形テストEffectでゲインの位置を識別し、44.1 / 48 / 96 kHzで送りレベル・Bypass・Master Gainからの独立性を検証。

# 0.0.7 — メーター文字描画のクラッシュ修正

- 0.0.6のクラッシュレポートはDARMeterViewの文字属性辞書生成中の例外を示していた。欠けた属性がフォント・色のどちらかはログから判別できない。
- メーターとGEQ／ノブの文字描画を共通化し、取得できなかったフォントや色を辞書へ入れない処理へ変更。フォントはmonospaced → system → fixed-pitchの順にフォールバック。
- 非有限・非正の文字サイズを正規化。
- nilのフォント／色、全フォント取得失敗、AU追加後の再描画を確認する回帰テストを追加。
- GUIの配置・音声チェインは変更なし。

# 0.0.6 — 専用GEQ UI・画面の再配置

- 15バンドEQを専用描画のフェーダー、目盛り、0 dBライン、定常応答カーブへ変更。
- Gainをノブに変更。Shift微調整、ダブルクリック0 dB、キーボード操作。
- Master GainをGEQ後、Limiter直前へ移動。過渡応答で配置を検証。
- メイン画面を1160×780ポイントの左右配置に変更。全体スクロールを廃止し、AU一覧のみ内部スクロール。

# 0.0.5 — メイン画面統合・ライブRack編集

- ミュート状態を起動後のStart/Stopや出力切替で維持。
- キャプチャ継続中のAU追加・削除・順序変更・保存復元。共有Rackへ変更を加える間はAudioOutputUnitStopで出力コールバックを同期停止し、完了後に再開。
- Rackをメインウィンドウに埋め込み。純正GUIはEditorから直接表示。
- 15バンドMaster Graphic EQへ置換、Limiter直前に配置。
- メイン画面のスクロール・サイズ変更対応。

# 0.0.3 — Milestone C / Audio Units

2026-11-12

- AUv2 Stereo Effectの列挙、追加、最大8インスタンス、Bypass、順序変更、削除。
- 純正CocoaエディタとAUGenericView fallback。
- AU RackのClassInfoを含むplist保存／復元。復元失敗時は元のRackを維持。
- Reported Latencyとスロットエラー表示。形式不一致・render失敗はdryで迂回。
- 固定バッファによるブロック処理、単調増加するsample time、出力レート変更時の再構成。
- 追加・削除・順序変更・保存復元は停止中のみ許可。Editor／Bypassは再生中も操作可。
- Apple標準AUの実レンダー・状態往復を含むASan/UBSanテストが通過。

AUv3、サイドチェイン、クラッシュ隔離、遅延補償、完全Rack Presetは未対応。

# 0.0.2 — The Dutchman BOX/DAR / Milestone B

2026-11-12

- Milestone A：ユーザーによる実機動作確認・受け入れ済み。
- アプリ表示名をThe Dutchman BOX/DARへ変更。ファイル名はスラッシュを避けThe Dutchman BOX-DAR.app。既存の権限設定との連続性のためbundle identifierと実行ファイル名は維持。
- 暗色のラックUI、入力／出力L/Rメーター（約30 fps）、−60〜0 dBFSスケール、1.5秒ピークホールド、クリックで解除するClip表示。バーは24 dB/sで減衰。
- Input Gain（−24〜+12 dB）→1バンドParametric EQ（20 Hz〜20 kHz、±12 dB、Q 0.2〜8）→Master Gain（−60〜+6 dB）→Limiter（−1 dBFS、左右連動、80 ms release）。各段Bypass可能。
- Gain／Bypassの遷移を平滑化。EQ設定もブロック単位で平滑化。
- 出力メーターはミュート後、入力メーターはDSP前。LimiterのGain Reductionを表示。
- ミュート解除後の状態表示をLIVEへ変更。
- DSP追加後もASan/UBSan付きバッファ試験が通過。EQ応答、複数レート、左右独立、Limiter ceiling、左右連動、Bypass、メーター集計の試験を追加して通過。

制限：Limiterはlookaheadなしのサンプルピーク方式で、true-peak保証はありません。Bypass中および切替クロスフェード中は上限保証対象外です。高品質SRC、Crossfeed、AU/VST3、HRTF、保存機能は後続段階。今回のGUI表示と実音声は、この実行環境にGUIセッションがないため未確認です。
