# Background Task

全域 Pi extension，讓 Shell 指令在背景執行，不阻塞對話。執行 `/reload` 後載入。

## 指令

```text
/bg                  # 開啟即時面板（TUI）
/bg panel            # 同上
/bg start bun test
/bg start npm run dev
/bg list
/bg output <id>       # 最近 200 行
/bg output <id> 1000  # 最多 2000 行 / 48 KiB
/bg stop <id>
/bg stop-all
/bg help
```

`start` 後的文字會原樣交給 `bash -c`（從 PATH 尋找 Bash；Home Manager 安裝 `pkgs.bash`），可使用引號、管線與多行指令。工作目錄預設為目前 session cwd。不要額外加 `&` 或自行 daemonize；由 extension 管理程序生命週期。沒有互動式 stdin 或 PTY。

## 即時監看面板

使用 `/bg`、`/bg panel` 或 **Ctrl+Shift+B** 開啟浮動面板，每 250 ms 更新，不呼叫模型，也不將監看內容寫入對話。

- 顯示任務列表、狀態、PID、執行時間、exit code、指令、cwd、log 路徑和 stdout/stderr。
- **↑ / ↓**：切換任務。
- **PgUp / PgDn**：凍結目前輸出快照並翻頁；**Home**：快照最前端。
- **Space**：暫停／恢復追蹤；**End / f**：回到即時最新輸出。
- **Esc / q / Ctrl+Shift+B**：關閉面板，**不停止背景任務**。
- 面板只顯示記憶體尾端的最近 2000 行；過長行依視窗寬度截短。ANSI 控制序列會移除，不是完整 terminal emulator。程序自身緩衝的輸出需等程序 flush 後才會出現。
- 關閉、reload 或 session shutdown 會清理面板更新計時器。停止任務請使用 `/bg stop <id>`。
- 需要互動式 TUI；RPC／headless 的裸 `/bg` 保留列表行為。若終端無法辨識 Ctrl+Shift+B，請使用 `/bg`。

## AI 工具

`background_task` 支援 `start | list | output | stop`。

```json
{"action":"start","command":"bun test","cwd":"./project","timeout":120}
{"action":"output","id":"<returned-id>","lines":200}
{"action":"stop","id":"<returned-id>"}
```

`timeout` 為秒數，省略則無時間限制。啟動成功只代表程序已建立，不代表工作成功；請檢查最終 status / exitCode。

## 生命週期與限制

- 面板內 Esc 只關閉面板；面板外 Esc 取消目前 agent turn。兩者都不停止已啟動的背景工作。
- `/reload`、退出、`/new`、`/resume`、`/fork` 等 session runtime 關閉時，停止背景工作。重新載入後不恢復任務列表，也不自動重跑指令。
- `/tree` 不會倒轉外部程序的副作用，任務仍由目前 runtime 管理。
- 停止時對程序群組發送 SIGTERM，再升級 SIGKILL。自行脫離群組的 daemon 無法保證清理；Pi 被 SIGKILL 或系統崩潰也無法執行關閉 hook。
- 最多 8 個 active 任務、100 筆任務記錄。記憶體僅保留最近 1 MiB 輸出；每個磁碟 log 最多 10 MiB。超出限制會截斷並標示，並非無限完整紀錄。
- stdout/stderr 合併；不同串流之間不保證精確順序。日誌存於系統暫存目錄，路徑顯示在結果中。可能含機密資訊；不自動刪除，以便離開 session 後排查。
- footer 顯示 active 任務數。完成時顯示通知，並把結果摘要排入下一個使用者回合；**不自動喚醒模型、不產生額外模型呼叫**。
- 支援 macOS/Linux；執行的是非互動 Bash，沒有載入 login shell 設定或 Pi 內建 Bash 的自訂 spawn hook。

## 安全

任務具有目前使用者完整權限，**不是 sandbox**。此工具名稱為 `background_task`，僅攔截內建 `bash` 的權限或 sandbox extension 不會自動涵蓋它；如有此類政策，必須另外整合後才啟用。不要用背景執行繞過批准流程。

## 驗證

```sh
cd common/home-base/pi # 從 dotfiles repo 根目錄
bun install --frozen-lockfile --ignore-scripts
bun test extensions/background-task/tests
```

整合測試使用 package.json / bun.lock 固定的本地 Pi 0.85.1 開發 SDK；不需要全域安裝或模型請求。
