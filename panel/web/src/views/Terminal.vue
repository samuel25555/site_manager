<script setup lang="ts">
import { ref, onMounted, onUnmounted, nextTick, watch } from "vue"
import { useRoute } from "vue-router"
import { Terminal } from "@xterm/xterm"
import { FitAddon } from "@xterm/addon-fit"
import { WebLinksAddon } from "@xterm/addon-web-links"
import Layout from "../components/Layout.vue"
import { Plus, X, SplitSquareHorizontal } from "lucide-vue-next"
import "@xterm/xterm/css/xterm.css"

interface TerminalPanel {
  id: number
  cwd: string
  terminal: Terminal | null
  fitAddon: FitAddon | null
  ws: WebSocket | null
  connected: boolean
  initialCdDone: boolean
  heartbeatTimer: number | null
  reconnectAttempts: number
}

interface TerminalTab {
  id: number
  name: string
  panels: TerminalPanel[]
}

const route = useRoute()
const tabs = ref<TerminalTab[]>([])
const activeTabId = ref<number>(0)
const activePanelId = ref<number>(0)
let idCounter = 0

// 心跳配置
const HEARTBEAT_INTERVAL = 30000  // 30秒发送一次心跳
const MAX_RECONNECT_ATTEMPTS = 3  // 最大重连次数

function getInitialCwd(): string {
  return (route.query.cwd as string) || ""
}

function createPanel(cwd: string = ""): TerminalPanel {
  return {
    id: ++idCounter,
    cwd: cwd || getInitialCwd(),
    terminal: null,
    fitAddon: null,
    ws: null,
    connected: false,
    initialCdDone: false,
    heartbeatTimer: null,
    reconnectAttempts: 0
  }
}

function createTab(cwd: string = "") {
  const panel = createPanel(cwd)
  const tab: TerminalTab = {
    id: ++idCounter,
    name: `终端 ${tabs.value.length + 1}`,
    panels: [panel]
  }
  tabs.value.push(tab)
  activeTabId.value = tab.id
  activePanelId.value = panel.id

  nextTick(() => {
    initPanel(panel)
    connectPanel(panel)
  })
}

async function splitTerminal() {
  const tab = tabs.value.find(t => t.id === activeTabId.value)
  if (!tab) return

  const currentPanel = tab.panels.find(p => p.id === activePanelId.value)

  let cwd = ""
  if (currentPanel && currentPanel.connected) {
    cwd = await getCwdFromPanel(currentPanel)
  }

  const panel = createPanel("")
  if (cwd) {
    panel.cwd = cwd
  }

  tab.panels.push(panel)
  activePanelId.value = panel.id

  nextTick(() => {
    initPanel(panel)
    connectPanel(panel, cwd)
    tab.panels.forEach(p => {
      p.fitAddon?.fit()
      sendResize(p)
    })
  })
}

function getCwdFromPanel(panel: TerminalPanel): Promise<string> {
  return new Promise((resolve) => {
    if (!panel.ws || panel.ws.readyState !== WebSocket.OPEN) {
      resolve("")
      return
    }

    const marker = `__CWD_${Date.now()}__`
    const cmd = `echo "${marker}$(pwd)${marker}"\r`

    let output = ""
    let timeoutId: ReturnType<typeof setTimeout>

    const originalOnmessage = panel.ws.onmessage

    panel.ws.onmessage = (event) => {
      if (originalOnmessage) {
        originalOnmessage.call(panel.ws!, event)
      }

      let data = ""
      if (event.data instanceof ArrayBuffer) {
        data = new TextDecoder().decode(event.data)
      } else {
        data = event.data
      }
      output += data

      const startIdx = output.indexOf(marker)
      if (startIdx !== -1) {
        const endIdx = output.indexOf(marker, startIdx + marker.length)
        if (endIdx !== -1) {
          const cwd = output.substring(startIdx + marker.length, endIdx).trim()
          clearTimeout(timeoutId)
          panel.ws!.onmessage = originalOnmessage
          resolve(cwd)
        }
      }
    }

    timeoutId = setTimeout(() => {
      if (panel.ws) {
        panel.ws.onmessage = originalOnmessage
      }
      resolve("")
    }, 1000)

    panel.ws.send(new TextEncoder().encode(cmd))
  })
}

function closePanel(tabId: number, panelId: number) {
  const tab = tabs.value.find(t => t.id === tabId)
  if (!tab) return

  const index = tab.panels.findIndex(p => p.id === panelId)
  if (index === -1) return

  const panel = tab.panels[index]
  if (panel) {
    stopHeartbeat(panel)
    disconnectPanel(panel)
    panel.terminal?.dispose()
  }

  tab.panels.splice(index, 1)

  if (tab.panels.length === 0) {
    closeTab(tabId)
  } else {
    if (activePanelId.value === panelId) {
      const newIndex = Math.max(0, index - 1)
      activePanelId.value = tab.panels[newIndex]?.id || 0
    }
    nextTick(() => {
      tab.panels.forEach(p => {
        p.fitAddon?.fit()
        sendResize(p)
      })
    })
  }
}

function closeTab(tabId: number) {
  const index = tabs.value.findIndex(t => t.id === tabId)
  if (index === -1) return

  const tab = tabs.value[index]
  if (tab) {
    tab.panels.forEach(panel => {
      stopHeartbeat(panel)
      disconnectPanel(panel)
      panel.terminal?.dispose()
    })
  }

  tabs.value.splice(index, 1)

  if (tabs.value.length === 0) {
    createTab()
  } else if (activeTabId.value === tabId) {
    const newIndex = Math.max(0, index - 1)
    activeTabId.value = tabs.value[newIndex]?.id || 0
    const newTab = tabs.value.find(t => t.id === activeTabId.value)
    activePanelId.value = newTab?.panels[0]?.id || 0
  }
}

function switchTab(tabId: number) {
  activeTabId.value = tabId
  const tab = tabs.value.find(t => t.id === tabId)
  if (tab && tab.panels.length > 0) {
    activePanelId.value = tab.panels[0]?.id || 0
  }
  nextTick(() => {
    tab?.panels.forEach(p => {
      p.fitAddon?.fit()
      sendResize(p)
    })
  })
}

function activatePanel(panelId: number) {
  activePanelId.value = panelId
  const tab = tabs.value.find(t => t.id === activeTabId.value)
  const panel = tab?.panels.find(p => p.id === panelId)
  panel?.terminal?.focus()
}

function initPanel(panel: TerminalPanel) {
  const container = document.getElementById(`panel-term-${panel.id}`)
  if (!container) return

  panel.terminal = new Terminal({
    cursorBlink: true,
    cursorStyle: "block",
    fontSize: 14,
    fontFamily: "JetBrains Mono, Fira Code, Consolas, monospace",
    theme: {
      background: "#1a1b26",
      foreground: "#a9b1d6",
      cursor: "#c0caf5",
      cursorAccent: "#1a1b26",
      selectionBackground: "#33467c",
      black: "#32344a",
      red: "#f7768e",
      green: "#9ece6a",
      yellow: "#e0af68",
      blue: "#7aa2f7",
      magenta: "#ad8ee6",
      cyan: "#449dab",
      white: "#787c99",
      brightBlack: "#444b6a",
      brightRed: "#ff7a93",
      brightGreen: "#b9f27c",
      brightYellow: "#ff9e64",
      brightBlue: "#7da6ff",
      brightMagenta: "#bb9af7",
      brightCyan: "#0db9d7",
      brightWhite: "#acb0d0"
    }
  })

  panel.fitAddon = new FitAddon()
  panel.terminal.loadAddon(panel.fitAddon)
  panel.terminal.loadAddon(new WebLinksAddon())

  panel.terminal.open(container)
  panel.fitAddon.fit()

  panel.terminal.onData((data) => {
    if (panel.ws?.readyState === WebSocket.OPEN) {
      panel.ws.send(new TextEncoder().encode(data))
    }
  })
}

// 心跳保活机制
function startHeartbeat(panel: TerminalPanel) {
  stopHeartbeat(panel)

  panel.heartbeatTimer = window.setInterval(() => {
    if (panel.ws?.readyState === WebSocket.OPEN) {
      // 发送心跳包 (opcode 2 表示心跳)
      const heartbeat = new Uint8Array([2])
      panel.ws.send(heartbeat)
    }
  }, HEARTBEAT_INTERVAL)
}

function stopHeartbeat(panel: TerminalPanel) {
  if (panel.heartbeatTimer) {
    clearInterval(panel.heartbeatTimer)
    panel.heartbeatTimer = null
  }
}

// 重连逻辑
function attemptReconnect(panel: TerminalPanel, cdTo?: string) {
  if (panel.reconnectAttempts >= MAX_RECONNECT_ATTEMPTS) {
    panel.terminal?.write("\r\n\x1b[31m[重连失败，已达最大重试次数]\x1b[0m\r\n")
    return
  }

  panel.reconnectAttempts++
  panel.terminal?.write(`\r\n\x1b[33m[正在重连... (${panel.reconnectAttempts}/${MAX_RECONNECT_ATTEMPTS})]\x1b[0m\r\n`)

  setTimeout(() => {
    connectPanel(panel, cdTo)
  }, 2000 * panel.reconnectAttempts)
}

function connectPanel(panel: TerminalPanel, cdTo?: string) {
  if (panel.ws?.readyState === WebSocket.OPEN) return

  const protocol = window.location.protocol === "https:" ? "wss:" : "ws:"
  const token = localStorage.getItem("token")
  const url = `${protocol}//${window.location.host}/ws/terminal?token=${token}`

  panel.ws = new WebSocket(url)
  panel.ws.binaryType = "arraybuffer"

  panel.ws.onopen = () => {
    panel.connected = true
    panel.reconnectAttempts = 0
    panel.terminal?.focus()
    sendResize(panel)
    startHeartbeat(panel)

    if (cdTo && !panel.initialCdDone) {
      panel.initialCdDone = true
      setTimeout(() => {
        if (panel.ws?.readyState === WebSocket.OPEN) {
          const cdCmd = `cd ${JSON.stringify(cdTo)} && clear\r`
          panel.ws.send(new TextEncoder().encode(cdCmd))
        }
      }, 300)
    }
  }

  panel.ws.onmessage = (event) => {
    if (event.data instanceof ArrayBuffer) {
      const data = new Uint8Array(event.data)
      // 检查是否是心跳响应 (opcode 3)
      if (data.length === 1 && data[0] === 3) {
        return
      }
      panel.terminal?.write(data)
    } else {
      panel.terminal?.write(event.data)
    }
  }

  panel.ws.onclose = (event) => {
    panel.connected = false
    stopHeartbeat(panel)

    // 非正常关闭时尝试重连
    if (event.code !== 1000 && event.code !== 1001) {
      attemptReconnect(panel, cdTo)
    } else {
      panel.terminal?.write("\r\n\x1b[31m[连接已断开]\x1b[0m\r\n")
    }
  }

  panel.ws.onerror = () => {
    // onclose 会随后被调用
  }
}

function disconnectPanel(panel: TerminalPanel) {
  stopHeartbeat(panel)
  panel.ws?.close(1000, "User disconnected")
  panel.ws = null
  panel.connected = false
}

function sendResize(panel: TerminalPanel) {
  if (!panel.ws || panel.ws.readyState !== WebSocket.OPEN || !panel.terminal) return

  const cols = panel.terminal.cols
  const rows = panel.terminal.rows

  const resizeCmd = new Uint8Array([
    1,
    (cols >> 8) & 0xff, cols & 0xff,
    (rows >> 8) & 0xff, rows & 0xff
  ])
  panel.ws.send(resizeCmd)
}

function handleResize() {
  const tab = tabs.value.find(t => t.id === activeTabId.value)
  tab?.panels.forEach(panel => {
    panel.fitAddon?.fit()
    sendResize(panel)
  })
}

watch(activeTabId, (newId) => {
  nextTick(() => {
    const tab = tabs.value.find(t => t.id === newId)
    tab?.panels.forEach(p => {
      p.fitAddon?.fit()
      sendResize(p)
    })
  })
})

onMounted(() => {
  createTab()
  window.addEventListener("resize", handleResize)
})

onUnmounted(() => {
  tabs.value.forEach(tab => {
    tab.panels.forEach(panel => {
      stopHeartbeat(panel)
      disconnectPanel(panel)
      panel.terminal?.dispose()
    })
  })
  window.removeEventListener("resize", handleResize)
})
</script>

<template>
  <Layout title="Web 终端" :full-height="true">
    <template #actions>
      <button
        @click="createTab()"
        class="p-2 rounded-lg bg-slate-700 hover:bg-slate-600 text-slate-400 hover:text-white transition"
        title="新建终端 Tab"
      >
        <Plus class="w-4 h-4" />
      </button>
      <button
        @click="splitTerminal()"
        class="p-2 rounded-lg bg-slate-700 hover:bg-slate-600 text-slate-400 hover:text-white transition"
        title="分屏（同步目录）"
      >
        <SplitSquareHorizontal class="w-4 h-4" />
      </button>
    </template>

    <div class="flex flex-col h-full">
      <!-- Tab 栏 -->
      <div class="flex items-center gap-1 px-2 py-1 bg-slate-800 border-b border-slate-700 overflow-x-auto">
        <button
          v-for="tab in tabs"
          :key="tab.id"
          @click="switchTab(tab.id)"
          class="group flex items-center gap-2 px-3 py-1.5 rounded text-sm transition-all min-w-0"
          :class="[
            activeTabId === tab.id
              ? 'bg-slate-700 text-white'
              : 'text-slate-400 hover:bg-slate-700/50 hover:text-white'
          ]"
        >
          <span
            class="w-2 h-2 rounded-full flex-shrink-0"
            :class="[tab.panels.every(p => p.connected) ? 'bg-green-500' : 'bg-red-500']"
          ></span>
          <span class="truncate">{{ tab.name }}</span>
          <span v-if="tab.panels.length > 1" class="text-xs text-slate-500">({{ tab.panels.length }})</span>
          <button
            v-if="tabs.length > 1"
            @click.stop="closeTab(tab.id)"
            class="p-0.5 rounded opacity-0 group-hover:opacity-100 hover:bg-slate-600 transition-all"
          >
            <X class="w-3 h-3" />
          </button>
        </button>
      </div>

      <!-- 终端区域 -->
      <div class="flex-1 bg-[#1a1b26] overflow-hidden relative">
        <div
          v-for="tab in tabs"
          :key="tab.id"
          class="absolute inset-0 flex"
          :style="{ display: tab.id === activeTabId ? 'flex' : 'none' }"
        >
          <div
            v-for="panel in tab.panels"
            :key="panel.id"
            class="terminal-panel"
            :class="{ 'active': activePanelId === panel.id }"
            @click="activatePanel(panel.id)"
          >
            <button
              v-if="tab.panels.length > 1"
              @click.stop="closePanel(tab.id, panel.id)"
              class="panel-close-btn"
            >
              <X class="w-3 h-3" />
            </button>
            <div :id="`panel-term-${panel.id}`" class="terminal-content"></div>
          </div>
        </div>
      </div>
    </div>
  </Layout>
</template>

<style>
.terminal-panel {
  flex: 1;
  min-width: 0;
  position: relative;
  border-right: 1px solid #334155;
  display: flex;
  flex-direction: column;
}

.terminal-panel:last-child {
  border-right: none;
}

.terminal-panel.active {
  outline: 1px solid #3b82f6;
  outline-offset: -1px;
}

.terminal-content {
  flex: 1;
  padding: 8px;
  overflow: hidden;
}

.terminal-content .xterm {
  height: 100%;
}

.panel-close-btn {
  position: absolute;
  top: 4px;
  right: 4px;
  z-index: 10;
  width: 22px;
  height: 22px;
  border-radius: 4px;
  background: rgba(51, 65, 85, 0.9);
  color: #94a3b8;
  border: none;
  cursor: pointer;
  display: flex;
  align-items: center;
  justify-content: center;
  opacity: 0;
  transition: all 0.2s;
}

.terminal-panel:hover .panel-close-btn {
  opacity: 1;
}

.panel-close-btn:hover {
  background: rgba(239, 68, 68, 0.9);
  color: white;
}
</style>
