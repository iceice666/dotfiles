# Todo extension

參考 [@juicesharp/rpiv-todo](https://www.npmjs.com/package/@juicesharp/rpiv-todo) 的工作流程，針對目前安裝的 `@earendil-works/pi-coding-agent` API 獨立實作。

位於 `~/.pi/agent/extensions/todo/index.ts`，Pi 會自動探索；在目前 session 執行 `/reload` 即可載入。不需安装 npm 套件，也不修改現有 footer。

## 用法

| 指令 | 用途 |
| --- | --- |
| `/todo`、`/todos` | 查看完整清單 |
| `/todo add 撰寫測試` | 新增待辦 |
| `/todo start 1` | 標為進行中 |
| `/todo done 1` | 標為完成 |
| `/todo pending 1` | 改回待辦 |
| `/todo edit 1 補齊整合測試` | 修改標題 |
| `/todo category 1 UI` | 設定／修改類別（名稱可包含空格） |
| `/todo category 1` | 清除類別 |
| `/todo remove 1` | 刪除；若被其他任務依賴則拒絕 |
| `/todo prune` | 刪除已完成項目，同時移除相關依賴 |
| `/todo clear` | 確認後清空全部 |
| `/todo collapse`、`/todo expand` | 收合／展開面板 |
| `/todo help` | 顯示指令說明 |

上述指令也接受 `/todos`。Todo 不註冊快捷鍵；使用 `/todo collapse` 或 `/todo expand` 收合／展開面板。`Ctrl+Shift+T` 保留給 agent-team。修改指令限 Agent 閒置時使用，檢視及收合不受此限制。

可直接告訴 Agent：「請把這項工作拆成待辦，逐項實作並更新狀態。」Agent 會取得 `todo` 工具及使用指引，但是否使用仍取決於模型。

## 未完成任務提醒

模型正常結束回答時，若仍有 `pending` 或 `in_progress` 項目，extension 會送出可見的提醒訊息（含未完成清單），並自動啟動一輪 follow-up，要求完成剩餘工作或用 `todo` 如實更新狀態。

- 每次使用者輸入（TUI／RPC）最多自動提醒一次，避免模型忽略提醒或遇到阻礙時無限續跑；extension 注入訊息與 compaction 不重設此限制。
- 空清單、全部完成、todo 工具未啟用、已有排隊訊息時不提醒。
- 只處理正常文字回答結束；取消、API 錯誤、長度截斷或工具終止不會強制重啟。
- 提醒不會自行修改待辦，並要求模型尊重暫停、授權與等待回覆的限制；受阻時保留未完成狀態、說明原因並停止，不得為了消除提醒而假報完成或清空任務。
- 純文字／JSON／RPC 模式同樣適用；自動 follow-up 會產生額外模型用量。

## Agent 工具

```json
{"action":"add","text":"實作功能","activeForm":"正在實作功能"}
{"action":"add","text":"驗證功能","blockedBy":[1]}
{"action":"update","id":1,"status":"in_progress"}
{"action":"update","id":1,"status":"completed"}
{"action":"list"}
```

### 批次新增

沿用 `add`，改傳 `items` 陣列；原本的單筆 `text` 用法保持相容：

```json
{
  "action": "add",
  "items": [
    { "text": "實作功能", "activeForm": "正在實作功能" },
    { "text": "撰寫測試" },
    { "text": "更新文件" }
  ]
}
```

- 每筆可填 `text`（必填）、`category`、`status`、`activeForm`、`blockedBy`；預設狀態為 `pending`。
- `items` 僅供 `add` 使用，不可與頂層 `id`、`text`、`category`、`status`、`activeForm`、`blockedBy` 混用。
- 一批 1–50 筆，新增後總數仍不得超過 50。ID 依陣列順序分配。
- **全有或全無**：任一筆不合法，整批不新增、不消耗 ID；成功只保存一次快照並更新一次面板。
- 依賴可指向既有任務或同批較早新增的任務 ID，不可指向同批後面的任務；不要假設清空後 ID 會從 1 重算。
- 批次介面提供給 Agent 工具；手動 `/todo add <內容>` 維持單筆新增。

動作：`list`、`add`、`update`、`remove`、`prune`、`clear`。
狀態：`pending`、`in_progress`、`completed`。
`blockedBy` 必須指向現有 ID；拒絕循環、自我依賴、不存在的依賴，以及依賴尚未完成時開始／完成任務。允許多個任務同時進行。`update` 傳 `blockedBy: []` 可解除依賴。工具的 `clear` 不彈確認視窗；模型指引要求不得擅自清空未完成工作。

### 任務類別

`add`（單筆與批次）及 `update` 支援選填的 `category`，適合長程任務按領域或階段分組：

```json
{"action":"add","items":[{"text":"Translate extension UI text into English and verify tests","category":"UI"},{"text":"Run UI test","category":"Verify"}]}
{"action":"update","id":1,"category":"UI polish"}
{"action":"update","id":1,"category":""}
```

省略 `category` 時保留既有類別；空字串或純空白字串清除類別。名稱去除首尾空白、區分大小寫，上限 60 字元，不接受控制字元。分類不影響 ID、狀態或跨類別依賴。舊快照不用遷移。

## 顯示與保存

有分類時的面板樣式：

```text
 TODO
  ├─ UI (1/1)
  │  └─ ☑ Translate extension UI text into English and verify tests
  └─ Verify (1/1)
     └─ ☑ Run UI test
```

- 類別依清單首次出現順序排列，比例按該類完整資料計算；混合清單中的未分類項目歸入 `Uncategorized`。
- 各類別保留最近完成的一項，再顯示進行中、待辦項目；收合時僅顯示類別與比例。
- 類別標題與任務共同計入行數預算；超出時顯示 `more rows`（收合時 `more categories`），可用 `/todos` 查看包含分類的完整清單。
- 全部未分類時沿用原面板與精簡方式：



```text
 TODO
  └─ Tasks · 8/9
     ├─ ☑ Finalize operational docs and remove smoke artifacts
     └─ ☐ Qualify actual GitHub workflow before enabling schedule (blocked)
```

- 輸入框上方顯示樹狀面板：已完成的 `☑` 與文字為綠色（theme `success`）；依賴尚未完成的任務及 `(blocked)` 為黃色（`warning`）；其他任務使用一般文字色（`text`），不加刪除線。
- **自動精簡顯示**：只保留最近完成的一項，再依序顯示進行中、待辦項目。完成順序由目前分支的快照還原，不以 ID 大小判定；進行中項目優先顯示 `activeForm`。
- 自動精簡不刪除資料，`Tasks · 已完成/總數` 仍按完整清單計算；`/todos` 及模型 context 保留全部項目。真正刪除已完成資料仍使用 `/todo prune`。
- 超出終端行數預算時顯示剩餘項目數與 `/todos` 提示；長文字按終端寬度截斷。未分類面板收合時只顯示標題與比例，不加額外底線；空清單隱藏面板。
- 變更以專屬 custom entry 快照寫入 **Pi 自己的 session**，不另建待辦 JSON 檔案；工具結果也包含快照供檢視。
- `/reload`、`/resume`、`/tree`、fork 和 compaction 後依目前 session 分支還原。新 session 是空清單，不同程序／子 Agent 各自獨立，沒有跨 session 同步。
- 每次模型請求都附上目前狀態（包含手動修改），不依賴舊工具結果或壓縮摘要。
- 純文字／JSON 模式仍可使用工具；TUI 專用面板不會在 headless 模式執行。RPC 使用文字 widget。
- 上限 50 項；標題 200 字元、進行中標籤 100 字元。拒絕控制字元。ID 單調遞增且有上限，不會因刪除／清空重用。
- 面板收合狀態只保留在記憶體，重新載入後展開。本版沒有外部設定檔或多語系套件依賴。

## 測試

```sh
cd common/home-base/pi # 從 dotfiles repo 根目錄
bun install --frozen-lockfile --ignore-scripts
bun test extensions/todo/tests
```

`model.test.ts` 驗證狀態規則；`extension.test.ts` 使用本機實際 Pi extension loader 搭配模擬 session/UI，驗證載入、並行更新、分支還原、取消、指令、模型 context 與窄螢幕顯示。整合測試使用 package.json / bun.lock 固定的本地 Pi 0.85.1 開發 SDK，不依賴全域安裝路徑。
