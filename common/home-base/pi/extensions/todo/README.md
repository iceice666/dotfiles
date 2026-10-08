# Todo extension

參考 [@juicesharp/rpiv-todo](https://www.npmjs.com/package/@juicesharp/rpiv-todo) 的工作流程，針對目前安裝的 `@earendil-works/pi-coding-agent` API 獨立實作。

由受管 `pi` launcher 從 Nix store 載入（見 `../../README.md`），部署後重新啟動 Pi。不需安裝 npm 套件，也不修改現有 footer。

## 用法

| 指令 | 用途 |
| --- | --- |
| `/todo`、`/todos` | 查看完整清單 |
| `/todo add 撰寫測試` | 新增待辦 |
| `/todo start 1` | 標為進行中 |
| `/todo done 1` | 標為完成；宣告 checks 的任務必須先通過新鮮驗證 |
| `/todo verify 1` | 以目前使用者權限實際執行已批准的 checks |
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

動作：`list`、`add`、`update`、`remove`、`prune`、`clear`、`verify`。
狀態：`pending`、`in_progress`、`completed`。
`blockedBy` 必須指向現有 ID；拒絕循環、自我依賴、不存在的依賴，以及依賴尚未完成時開始／完成任務。允許多個任務同時進行。`update` 傳 `blockedBy: []` 可解除依賴。工具的 `clear` 不彈確認視窗；模型指引要求不得擅自清空未完成工作。

### 選用的完成驗證閘門

一般任務的行為不變。只有在新增時明確提供 `checks` 的任務才套用閘門：

```json
{"action":"add","text":"實作並驗證功能","checks":[{"name":"unit","command":"bun test"}]}
{"action":"verify","id":1}
{"action":"update","id":1,"status":"completed"}
```

- 每項 1–10 個具唯一名稱的 checks；名称上限 100 字元、單行命令上限 4000 字元。批次每筆也可帶 checks。新增時透過 `ask-question/approval.ts` 的單次人類授權 UI，顯示完整命令、任務描述及 canonical cwd；worker 經團隊 broker 路由至真正人類。取消、拒絕、無 UI／broker 都不算同意，整批不新增。這只批准要求宣告，不授予 host/network 權限。
- 描述及命令新增後不可更改；工具參數不能注入 approval／evidence。批准的原始 canonical cwd 與時間保存在 session。恢復至其他目錄、舊快照缺少批准欄位時，驗證一律阻擋，不會把當前目錄當成已批准目錄；回原始目錄使用，缺少批准的舊任務需人工處理。
- `verify` 不接受命令或自報的測試結果，只透過 `../local-process.mjs` 實際執行已批准的命令。使用目前程序的環境及使用者權限，沒有 Pi OS sandbox 或網路隔離；批准 checks 前需確認命令的主機及外部副作用。launcher 以 `PI_TOOL_BASH`／`PI_TOOL_NODE`／`PI_TOOL_GIT` 固定工具；開發環境可使用 PATH 與目前 Node/Bun runtime。無法啟動或執行失敗不會產生成功證據。
- 每個 check 最多 120 秒、stdout/stderr 合計最多捕捉 10 MiB；超量、超時、signal、取消、啟動失敗及非零退出碼都不通過。記錄實際退出狀態、開始／结束時間、耗時與最後 12KB／200 行輸出（截斷有標記），逐項失敗即停止。紀錄位於 `local-todo-verification-v1` custom entry；只是 audit history，不能作為恢復後的新證據。
- 檢查前後的 worktree fingerprint 必須一致，完成／移除／prune／clear 前也重新檢查。fingerprint 由固定的本機程式計算，停用 Git hooks、fsmonitor 及 optional locks，包含 tracked + nonignored untracked 檔案內容、mode、inode、修改時間、Git refs/index/config；修改後即使改回同樣內容，也通常因 metadata 改變而失效。限本地 `.git` 目錄的 Git root，不支援 linked worktree／submodule、特殊檔案、symlink ancestor；最多 100000 檔案／256 MiB。忽略檔案及外部依賴不納入；這不是完整 hermetic build 或對惡意外部程序的原子快照。
- 只有目前程序剛執行成功且內容仍相符的 live evidence 可以允許完成；模型不能以文字聲稱完成，也不能刪除或清空未完成閘門來繞過。檔案變更、fingerprint 錯誤、reload/resume/fork/tree 會讓證據失效，已完成閘門及其遞迴依賴者回到 pending，保留依賴圖。compaction 保留本程序的證據，但仍重新比對 fingerprint；不需要無故重跑檢查。
- 取消／超時會終止 process group 並限制等待時間；刻意脫離 process group 的後代可能繼續以使用者權限執行，沒有 kernel sandbox 限制。成功驗證不保證沒有背景程序；請勿使用 daemon／背景工作作為 checks。
- Todo 操作串行執行；其他工具或程序仍可能平行編輯，因此要先停止修改再驗證。驗證結束後再次比對發現變更時會回報失敗，而不誤報成功。證據只證明已批准命令確實成功執行，不保證命令本身涵蓋所有需求。

### 精簡輸出與快取

- `list` 回傳完整清單；新增／更新只回傳變動項目與完成比例，刪除會列出移除的 ID。`prune` 也回報依賴被清掉的項目。
- 工具結果的 `details.state` 仍保存完整快照，展開結果與面板不受影響。一般更新不另塞一份清單進模型 context。
- 不再於每次模型請求尾端重建 todo 訊息；歷史訊息保持原位，避免 Claude 的 cache breakpoint 落在下一輪會消失的臨時尾端。
- 手動修改追加不啟動模型回合的狀態更新；恢復分支／session 時在下次輸入補一次完整快照。壓縮後補一次持久快照；只有既定的 overflow retry 使用 steering，不因狀態同步額外續跑。
- 無待辦的新 session 不注入空清單。曾清空的清單在恢復時仍明確同步，避免舊摘要讓模型誤以為任務尚在。
- 本機離線樣本：20 項任務、批次新增後逐項開始／完成，共 41 次工具呼叫；結果文字由 39,461 減至 3,541 字元（約 91%）。這是字元量，不是 tokenizer 或實際帳單測量；未計入移除每輪完整清單的額外節省。

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
- 自動精簡不刪除資料，`Tasks · 已完成/總數` 仍按完整清單計算；`/todos`、工具 `list` 與恢復快照保留全部項目。真正刪除已完成資料仍使用 `/todo prune`。
- 超出終端行數預算時顯示剩餘項目數與 `/todos` 提示；長文字按終端寬度截斷。未分類面板收合時只顯示標題與比例，不加額外底線；空清單隱藏面板。
- 變更以專屬 custom entry 快照寫入 **Pi 自己的 session**，不另建待辦 JSON 檔案；工具結果也包含快照供檢視。
- `/reload`、`/resume`、`/tree`、fork 和 compaction 後依目前 session 分支還原。新 session 是空清單，不同程序／子 Agent 各自獨立，沒有跨 session 同步。
- 模型透過持久的工具結果／手動更新及恢復快照取得狀態；不改寫舊訊息，也不每輪重送完整清單。壓縮摘要不是待辦狀態的唯一來源。
- 純文字／JSON 模式仍可使用工具；TUI 專用面板不會在 headless 模式執行。RPC 使用文字 widget。
- 上限 50 項；標題 200 字元、進行中標籤 100 字元。拒絕控制字元。ID 單調遞增且有上限，不會因刪除／清空重用。
- 面板收合狀態只保留在記憶體，重新載入後展開。本版沒有外部設定檔或多語系套件依賴。

## 測試

```sh
cd common/home-base/pi # 從 dotfiles repo 根目錄
bun install --frozen-lockfile --ignore-scripts
bun test extensions/todo/tests
```

`model.test.ts` 驗證狀態規則；`verification.test.ts` 與 `gate-extension.test.ts` 使用注入的離線 backend／人類授權 mock 驗證不可自證、cwd binding、取消、stale evidence、compaction、依賴重開與生命週期（不是 OS sandbox 安全測試）；`process.test.ts` 在 Linux/macOS 上用合成環境實際驗證 fingerprint、Git PATH fallback、cwd／環境繼承、退出碼、取消、超時及輸出上限；`extension.test.ts` 使用本機實際 Pi extension loader 搭配模擬 session/UI，驗證並行更新、分支還原、取消、指令、精簡輸出與窄螢幕顯示。快取回歸測試攔截實際 Anthropic adapter 的序列化請求，比對連續回合的前綴；自動壓縮測試使用真正 Pi session 與離線 provider，確認恢復快照不多啟動模型回合。測試不讀取真實憑證、不發送模型網路請求，SDK 固定為 package.json / bun.lock 的 Pi 0.85.1。
