# Ask user question

獨立 Pi extension，提供 `ask_user_question`；參考
[@juicesharp/rpiv-ask-user-question](https://www.npmjs.com/package/@juicesharp/rpiv-ask-user-question)
的選項式提問設計，採用本地實作，不需要安裝該 npm 套件。

放在 `~/.pi/agent/extensions/ask-question/` 後重新啟動或 `/reload`。
輸入 `/ask-question` 可直接預覽對話框，不需要模型呼叫；結果只顯示通知。

```json
{
  "questions": [
    {
      "header": "測試策略",
      "question": "需要哪些測試？",
      "options": [
        { "label": "單元測試", "description": "快速檢查獨立邏輯" },
        { "label": "整合測試", "description": "驗證元件之間的互動" }
      ],
      "multiSelect": true
    }
  ]
}
```

- 每次 1–4 題，TUI 使用繁體中文提示與有框面板，暫時取代底部普通 prompt 輸入區（不是浮動視窗）。送出或取消後由 Pi 恢復原本輸入框及其草稿。
- 頂部分頁顯示各題完成狀態；**Tab 下一題、Shift+Tab 上一題**，在文字編輯中也有效。非編輯模式亦可 ←→ 切換。
- 每題保留選項、游標及多行文字草稿，返回可修改；Tab 可以跳過未答題，但不能送出不完整問卷。
- 上下選項、Enter 單選並前往下一題、Space/Enter 切換複選；複選選「下一題 / 檢查答案」繼續。
- 「自訂文字（多行）」可自行作答；複選可同時保留選項與文字。沒有選項時直接開啟文字編輯。
- 使用 Pi 原生 **Editor** 並傳遞 IME 焦點；**Enter 換行、Ctrl+S 下一題**。支援多行貼上，答案會展開 Pi 的長貼上標記。
- 所有題目（含單題）最後必須在「檢查並送出」分頁 **Enter 明確送出整份問卷**，不會因選取答案就直接提交。
- **Ctrl+O 全文**可檢視完整問題與所有選項說明；檢查分頁可檢視完整答案。↑↓ 捲動、Ctrl+O 或 Esc 返回。
- 編輯模式 Esc 返回選項（無選項則取消）；一般模式 Esc 或任何模式 Ctrl+C 取消整份問卷，不回傳部分答案。
- RPC 保留 host 原生 select/input 的依序提問降級介面（沒有分頁/自訂問答面板）；複選反覆切換後選「完成」。取消不回傳部分答案。
- 非互動模式回傳 `unavailable`，不猜測答案，也不視為同意。
- 所有提問共用 FIFO，與 `agent_ask(to: "user")` 共用。取消排隊中的提問不會稍後彈出。
- 工具中止、session shutdown/reload 會取消等待。Team worker 不啟用此工具，改用
  `agent_ask` 的 `to: "user"` 將問題轉交主視窗。

`service.ts` 匯出 `askQuestions(ctx, { questions }, signal?)`、`QuestionFields`、
`QuestionSchema`、`QuestionsSchema`、`validateQuestions` 和相關型別。

```json
{
  "status": "answered",
  "answers": [
    { "question": "需要哪些測試？", "selected": ["單元測試"], "customText": "另外加入 smoke test" }
  ]
}
```

`status` 為 `answered`、`cancelled` 或 `unavailable`；後兩者 `answers` 為空。
單選自訂答案 `selected` 為空。工具文字輸出超過 48KB 時摘要截短，`details` 保留完整結果。

限制：問題 12000 字元、標頭 120、最多 12 選項、label 1000、description 4000；
整份請求 JSON 最多 24000 字元，自訂答案最多 4000。拒絕重複/空白 label 與終端控制字元。
TUI 面板最多 24 行並隨終端高度縮小，選項採用有界視窗。一般畫面摘要截短，Ctrl+O 可捲動全文；
極小終端（寬度小於 6 或高度小於 8）提示放大，仍可 Ctrl+C 取消。
文字答案上限含原始空白；空白或超過上限不能送出。尚未支援 markdown 預覽、外部編輯器或滑鼠分頁。

## 驗證

```sh
cd common/home-base/pi # 從 dotfiles repo 根目錄
bun install --frozen-lockfile --ignore-scripts
bun test extensions/ask-question/tests
```

測試使用 package.json / bun.lock 固定的本地 Pi 0.85.1 開發 SDK，直接操作實際元件的按鍵序列，覆蓋單/複選、
分頁往返與草稿保留、多行/長貼上展開、IME 游標標記、明確提交與缺答阻擋、全文捲動、
窄/矮終端、RPC、取消與 shutdown、跨 loader 排隊和輸入驗證，不需要模型請求；開發依賴只安裝於 checkout，不會部署到 Home Manager。
