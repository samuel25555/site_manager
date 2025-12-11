<script setup lang="ts">
import { ref, onMounted, computed } from "vue"
import { api } from "../stores/auth"
import Layout from "../components/Layout.vue"
import {
  FileText, Search, Trash2, RefreshCw, Loader2, Filter,
  Server, Database, Code, Shield, AlertCircle, ChevronDown
} from "lucide-vue-next"

interface LogFile {
  name: string
  path: string
  category: string
  exists: boolean
  size: number
}

const logFiles = ref<LogFile[]>([])
const loading = ref(true)
const selectedLog = ref<LogFile | null>(null)
const logContent = ref<string[]>([])
const loadingContent = ref(false)
const searchKeyword = ref("")
const lineCount = ref(100)
const categoryFilter = ref("")

const categories = [
  { value: "", label: "全部分类" },
  { value: "web", label: "Web 服务器" },
  { value: "php", label: "PHP" },
  { value: "database", label: "数据库" },
  { value: "system", label: "系统" },
  { value: "site", label: "站点" },
  { value: "firewall", label: "防火墙" },
  { value: "process", label: "进程管理" }
]

const categoryIcons: Record<string, any> = {
  web: Server,
  php: Code,
  database: Database,
  system: AlertCircle,
  site: FileText,
  firewall: Shield,
  process: Server
}

function formatSize(bytes: number): string {
  if (bytes === 0) return "0 B"
  const k = 1024
  const sizes = ["B", "KB", "MB", "GB"]
  const i = Math.floor(Math.log(bytes) / Math.log(k))
  return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + " " + sizes[i]
}

const filteredLogs = computed(() => {
  if (!categoryFilter.value) return logFiles.value
  return logFiles.value.filter(l => l.category === categoryFilter.value)
})

async function fetchLogFiles() {
  loading.value = true
  try {
    const res = await api.get("/logs")
    if (res.data.status) {
      logFiles.value = res.data.data || []
    }
  } catch (e) {
    console.error("Failed to fetch log files:", e)
  } finally {
    loading.value = false
  }
}

async function selectLog(log: LogFile) {
  if (!log.exists) return
  selectedLog.value = log
  searchKeyword.value = ""
  await readLog()
}

async function readLog() {
  if (!selectedLog.value) return
  loadingContent.value = true
  try {
    const params = new URLSearchParams({
      path: selectedLog.value.path,
      lines: lineCount.value.toString()
    })
    const res = await api.get("/logs/read?" + params.toString())
    if (res.data.status) {
      logContent.value = res.data.data.lines || []
    }
  } catch (e) {
    console.error("Failed to read log:", e)
    logContent.value = ["读取日志失败"]
  } finally {
    loadingContent.value = false
  }
}

async function searchLog() {
  if (!selectedLog.value || !searchKeyword.value.trim()) {
    await readLog()
    return
  }
  loadingContent.value = true
  try {
    const params = new URLSearchParams({
      path: selectedLog.value.path,
      keyword: searchKeyword.value,
      lines: lineCount.value.toString()
    })
    const res = await api.get("/logs/search?" + params.toString())
    if (res.data.status) {
      logContent.value = res.data.data.lines || []
    }
  } catch (e) {
    console.error("Failed to search log:", e)
  } finally {
    loadingContent.value = false
  }
}

async function clearLog() {
  if (!selectedLog.value) return
  if (!confirm("确定要清空此日志文件吗？此操作不可恢复。")) return

  try {
    const res = await api.post("/logs/clear", { path: selectedLog.value.path })
    if (res.data.status) {
      logContent.value = []
      await fetchLogFiles()
    } else {
      alert("清空失败: " + res.data.message)
    }
  } catch (e: any) {
    alert("清空失败: " + (e.response?.data?.message || e.message))
  }
}

onMounted(fetchLogFiles)
</script>

<template>
  <Layout title="日志查看器">
    <template #actions>
      <button @click="fetchLogFiles" :disabled="loading" class="p-2 rounded-lg bg-slate-700 hover:bg-slate-600 text-slate-400 hover:text-white transition">
        <RefreshCw :class="['w-4 h-4', loading && 'animate-spin']" />
      </button>
    </template>

    <div class="flex h-full gap-4">
      <!-- 左侧日志列表 -->
      <div class="w-72 flex-shrink-0 bg-slate-800 rounded-xl overflow-hidden flex flex-col">
        <!-- 分类筛选 -->
        <div class="p-3 border-b border-slate-700">
          <div class="relative">
            <select
              v-model="categoryFilter"
              class="w-full bg-slate-700 text-white rounded-lg px-3 py-2 pr-8 text-sm appearance-none focus:outline-none focus:ring-2 focus:ring-blue-500"
            >
              <option v-for="cat in categories" :key="cat.value" :value="cat.value">
                {{ cat.label }}
              </option>
            </select>
            <ChevronDown class="absolute right-2 top-1/2 -translate-y-1/2 w-4 h-4 text-slate-400 pointer-events-none" />
          </div>
        </div>

        <!-- 日志文件列表 -->
        <div class="flex-1 overflow-y-auto p-2 space-y-1">
          <div v-if="loading" class="flex items-center justify-center py-8">
            <Loader2 class="w-6 h-6 text-blue-500 animate-spin" />
          </div>
          <template v-else>
            <button
              v-for="log in filteredLogs"
              :key="log.path"
              @click="selectLog(log)"
              :disabled="!log.exists"
              class="w-full text-left p-3 rounded-lg transition"
              :class="[
                selectedLog?.path === log.path
                  ? 'bg-blue-600 text-white'
                  : log.exists
                    ? 'hover:bg-slate-700 text-slate-300'
                    : 'opacity-50 cursor-not-allowed text-slate-500'
              ]"
            >
              <div class="flex items-center gap-2 mb-1">
                <component
                  :is="categoryIcons[log.category] || FileText"
                  class="w-4 h-4"
                  :class="selectedLog?.path === log.path ? 'text-white' : 'text-slate-400'"
                />
                <span class="font-medium text-sm truncate">{{ log.name }}</span>
              </div>
              <div class="flex items-center justify-between text-xs" :class="selectedLog?.path === log.path ? 'text-blue-200' : 'text-slate-500'">
                <span>{{ log.exists ? formatSize(log.size) : '不存在' }}</span>
                <span class="px-1.5 py-0.5 rounded text-xs" :class="selectedLog?.path === log.path ? 'bg-blue-500' : 'bg-slate-700'">
                  {{ log.category }}
                </span>
              </div>
            </button>
          </template>
        </div>
      </div>

      <!-- 右侧日志内容 -->
      <div class="flex-1 bg-slate-800 rounded-xl overflow-hidden flex flex-col">
        <template v-if="selectedLog">
          <!-- 工具栏 -->
          <div class="p-3 border-b border-slate-700 flex items-center gap-3">
            <div class="flex-1 flex items-center gap-2">
              <div class="relative flex-1 max-w-md">
                <Search class="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-slate-400" />
                <input
                  v-model="searchKeyword"
                  @keyup.enter="searchLog"
                  type="text"
                  placeholder="搜索关键词..."
                  class="w-full bg-slate-700 text-white rounded-lg pl-9 pr-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500"
                />
              </div>
              <select
                v-model="lineCount"
                @change="readLog"
                class="bg-slate-700 text-white rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500"
              >
                <option :value="50">50 行</option>
                <option :value="100">100 行</option>
                <option :value="200">200 行</option>
                <option :value="500">500 行</option>
                <option :value="1000">1000 行</option>
              </select>
              <button
                @click="searchLog"
                class="px-3 py-2 bg-blue-600 hover:bg-blue-700 text-white rounded-lg text-sm transition flex items-center gap-1.5"
              >
                <Filter class="w-4 h-4" />
                筛选
              </button>
            </div>
            <div class="flex items-center gap-2">
              <button
                @click="readLog"
                :disabled="loadingContent"
                class="p-2 rounded-lg bg-slate-700 hover:bg-slate-600 text-slate-400 hover:text-white transition"
                title="刷新"
              >
                <RefreshCw :class="['w-4 h-4', loadingContent && 'animate-spin']" />
              </button>
              <button
                @click="clearLog"
                class="p-2 rounded-lg bg-red-600/20 hover:bg-red-600 text-red-400 hover:text-white transition"
                title="清空日志"
              >
                <Trash2 class="w-4 h-4" />
              </button>
            </div>
          </div>

          <!-- 日志内容 -->
          <div class="flex-1 overflow-auto p-4">
            <div v-if="loadingContent" class="flex items-center justify-center h-full">
              <Loader2 class="w-8 h-8 text-blue-500 animate-spin" />
            </div>
            <div v-else-if="logContent.length === 0" class="flex flex-col items-center justify-center h-full text-slate-500">
              <FileText class="w-12 h-12 mb-2" />
              <p>日志为空</p>
            </div>
            <pre v-else class="text-xs font-mono text-slate-300 whitespace-pre-wrap break-all"><template v-for="(line, i) in logContent" :key="i"><span class="text-slate-500 select-none mr-3">{{ String(i + 1).padStart(4, ' ') }}</span>{{ line }}
</template></pre>
          </div>

          <!-- 状态栏 -->
          <div class="px-4 py-2 border-t border-slate-700 text-xs text-slate-500 flex items-center justify-between">
            <span>{{ selectedLog.path }}</span>
            <span>共 {{ logContent.length }} 行</span>
          </div>
        </template>

        <!-- 未选择日志 -->
        <div v-else class="flex-1 flex flex-col items-center justify-center text-slate-500">
          <FileText class="w-16 h-16 mb-4" />
          <p class="text-lg">选择一个日志文件查看</p>
          <p class="text-sm mt-1">从左侧列表中选择要查看的日志</p>
        </div>
      </div>
    </div>
  </Layout>
</template>
