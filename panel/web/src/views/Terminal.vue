<script setup lang="ts">
import { ref, onMounted, onUnmounted, nextTick } from "vue"
import { Terminal } from "@xterm/xterm"
import { FitAddon } from "@xterm/addon-fit"
import { WebLinksAddon } from "@xterm/addon-web-links"
import Layout from "../components/Layout.vue"
import "@xterm/xterm/css/xterm.css"

const terminalRef = ref<HTMLDivElement | null>(null)
const connected = ref(false)
const status = ref("准备连接...")

let terminal: Terminal | null = null
let fitAddon: FitAddon | null = null
let ws: WebSocket | null = null
let reconnectTimer: number | null = null

function connect() {
  if (ws?.readyState === WebSocket.OPEN) return

  status.value = "连接中..."

  const protocol = window.location.protocol === "https:" ? "wss:" : "ws:"
  const token = localStorage.getItem("token")
  ws = new WebSocket(protocol + "//" + window.location.host + "/ws/terminal?token=" + token)

  ws.binaryType = "arraybuffer"

  ws.onopen = () => {
    connected.value = true
    status.value = "已连接"
    terminal?.focus()
    sendResize()
  }

  ws.onmessage = (event) => {
    if (event.data instanceof ArrayBuffer) {
      terminal?.write(new Uint8Array(event.data))
    } else {
      terminal?.write(event.data)
    }
  }

  ws.onclose = () => {
    connected.value = false
    status.value = "连接已断开"
    terminal?.write("\r\n\x1b[31m[连接已断开，5秒后重连...]\x1b[0m\r\n")
    scheduleReconnect()
  }

  ws.onerror = () => {
    status.value = "连接错误"
  }
}

function scheduleReconnect() {
  if (reconnectTimer) clearTimeout(reconnectTimer)
  reconnectTimer = window.setTimeout(() => {
    if (!connected.value) {
      connect()
    }
  }, 5000)
}

function disconnect() {
  if (reconnectTimer) {
    clearTimeout(reconnectTimer)
    reconnectTimer = null
  }
  ws?.close()
  ws = null
  connected.value = false
  status.value = "已断开"
}

function sendResize() {
  if (!ws || ws.readyState !== WebSocket.OPEN || !terminal) return

  const cols = terminal.cols
  const rows = terminal.rows

  const resizeCmd = new Uint8Array([
    1,
    (cols >> 8) & 0xff, cols & 0xff,
    (rows >> 8) & 0xff, rows & 0xff
  ])
  ws.send(resizeCmd)
}

function initTerminal() {
  if (!terminalRef.value) return

  terminal = new Terminal({
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

  fitAddon = new FitAddon()
  terminal.loadAddon(fitAddon)
  terminal.loadAddon(new WebLinksAddon())

  terminal.open(terminalRef.value)
  fitAddon.fit()

  terminal.onData((data) => {
    if (ws?.readyState === WebSocket.OPEN) {
      ws.send(new TextEncoder().encode(data))
    }
  })

  window.addEventListener("resize", handleResize)
}

function handleResize() {
  if (fitAddon) {
    fitAddon.fit()
    sendResize()
  }
}

onMounted(async () => {
  await nextTick()
  initTerminal()
  connect()
})

onUnmounted(() => {
  disconnect()
  terminal?.dispose()
  window.removeEventListener("resize", handleResize)
})
</script>

<template>
  <Layout title="Web 终端" :full-height="true">
    <template #actions>
      <span
        class="px-2 py-0.5 rounded text-xs"
        :class="[connected ? 'bg-green-600 text-white' : 'bg-red-600 text-white']"
      >
        {{ status }}
      </span>
      <button
        v-if="!connected"
        @click="connect"
        class="px-3 py-1.5 bg-green-600 hover:bg-green-700 text-white rounded text-sm transition"
      >
        连接
      </button>
      <button
        v-else
        @click="disconnect"
        class="px-3 py-1.5 bg-red-600 hover:bg-red-700 text-white rounded text-sm transition"
      >
        断开
      </button>
    </template>

    <div ref="terminalRef" class="terminal-container"></div>
  </Layout>
</template>

<style>
.terminal-container {
  height: calc(100vh - 180px);
  background: #1a1b26;
  border-radius: 8px;
  overflow: hidden;
}
.xterm {
  height: 100%;
  padding: 8px;
}
</style>
