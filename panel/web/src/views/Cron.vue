<script setup lang="ts">
import { ref, onMounted, computed } from "vue"
import { api } from "../stores/auth"
import Layout from "../components/Layout.vue"
import {
  Clock, Plus, Play, Pause, Trash2, RefreshCw, Loader2,
  Edit2, X, Check, AlertTriangle, Terminal
} from "lucide-vue-next"

interface CronJob {
  id: number
  minute: string
  hour: string
  day: string
  month: string
  weekday: string
  command: string
  user: string
  enabled: boolean
  schedule: string
}

const jobs = ref<CronJob[]>([])
const loading = ref(true)
const actionLoading = ref("")
const showModal = ref(false)
const editingJob = ref<CronJob | null>(null)
const showRunModal = ref(false)
const runOutput = ref("")
const runLoading = ref(false)

const form = ref({
  minute: "*",
  hour: "*",
  day: "*",
  month: "*",
  weekday: "*",
  command: "",
  user: "root"
})

const presets = [
  { label: "每分钟", value: { minute: "*", hour: "*", day: "*", month: "*", weekday: "*" } },
  { label: "每小时", value: { minute: "0", hour: "*", day: "*", month: "*", weekday: "*" } },
  { label: "每天凌晨", value: { minute: "0", hour: "0", day: "*", month: "*", weekday: "*" } },
  { label: "每天中午", value: { minute: "0", hour: "12", day: "*", month: "*", weekday: "*" } },
  { label: "每周日凌晨", value: { minute: "0", hour: "0", day: "*", month: "*", weekday: "0" } },
  { label: "每月1号", value: { minute: "0", hour: "0", day: "1", month: "*", weekday: "*" } },
]

const cronExpression = computed(() => {
  return `${form.value.minute} ${form.value.hour} ${form.value.day} ${form.value.month} ${form.value.weekday}`
})

const enabledCount = computed(() => jobs.value.filter(j => j.enabled).length)

async function fetchJobs() {
  loading.value = true
  try {
    const res = await api.get("/cron")
    if (res.data.status) {
      jobs.value = res.data.data || []
    }
  } catch (e) {
    console.error("Failed to fetch cron jobs:", e)
  } finally {
    loading.value = false
  }
}

function openCreateModal() {
  editingJob.value = null
  form.value = {
    minute: "*",
    hour: "*",
    day: "*",
    month: "*",
    weekday: "*",
    command: "",
    user: "root"
  }
  showModal.value = true
}

function openEditModal(job: CronJob) {
  editingJob.value = job
  form.value = {
    minute: job.minute,
    hour: job.hour,
    day: job.day,
    month: job.month,
    weekday: job.weekday,
    command: job.command,
    user: job.user
  }
  showModal.value = true
}

function applyPreset(preset: typeof presets[0]) {
  Object.assign(form.value, preset.value)
}

async function saveJob() {
  if (!form.value.command.trim()) {
    alert("请输入命令")
    return
  }

  actionLoading.value = "save"
  try {
    if (editingJob.value) {
      const res = await api.put(`/cron/${editingJob.value.id}`, form.value)
      if (!res.data.status) {
        alert("更新失败: " + res.data.message)
        return
      }
    } else {
      const res = await api.post("/cron", form.value)
      if (!res.data.status) {
        alert("创建失败: " + res.data.message)
        return
      }
    }
    showModal.value = false
    await fetchJobs()
  } catch (e: any) {
    alert("操作失败: " + (e.response?.data?.message || e.message))
  } finally {
    actionLoading.value = ""
  }
}

async function toggleJob(job: CronJob) {
  actionLoading.value = `toggle-${job.id}`
  try {
    const res = await api.post(`/cron/${job.id}/toggle`)
    if (res.data.status) {
      await fetchJobs()
    } else {
      alert("操作失败: " + res.data.message)
    }
  } catch (e: any) {
    alert("操作失败: " + (e.response?.data?.message || e.message))
  } finally {
    actionLoading.value = ""
  }
}

async function deleteJob(job: CronJob) {
  if (!confirm(`确定要删除此计划任务吗？\n命令: ${job.command}`)) return

  actionLoading.value = `delete-${job.id}`
  try {
    const res = await api.delete(`/cron/${job.id}`)
    if (res.data.status) {
      await fetchJobs()
    } else {
      alert("删除失败: " + res.data.message)
    }
  } catch (e: any) {
    alert("删除失败: " + (e.response?.data?.message || e.message))
  } finally {
    actionLoading.value = ""
  }
}

async function runNow(job: CronJob) {
  showRunModal.value = true
  runOutput.value = ""
  runLoading.value = true

  try {
    const res = await api.post("/cron/run", { command: job.command })
    runOutput.value = res.data.data?.output || "命令执行完成（无输出）"
  } catch (e: any) {
    runOutput.value = "执行失败: " + (e.response?.data?.message || e.message)
  } finally {
    runLoading.value = false
  }
}

onMounted(fetchJobs)
</script>

<template>
  <Layout title="计划任务">
    <template #actions>
      <button
        @click="openCreateModal"
        class="flex items-center gap-2 px-4 py-2 bg-blue-600 hover:bg-blue-700 text-white rounded-lg transition"
      >
        <Plus class="w-4 h-4" />
        添加任务
      </button>
      <button
        @click="fetchJobs"
        :disabled="loading"
        class="p-2 rounded-lg bg-slate-700 hover:bg-slate-600 text-slate-400 hover:text-white transition"
      >
        <RefreshCw :class="['w-4 h-4', loading && 'animate-spin']" />
      </button>
    </template>

    <div class="p-6">
      <!-- Stats -->
      <div class="grid grid-cols-3 gap-4 mb-6">
        <div class="bg-slate-800 rounded-lg p-4">
          <div class="flex items-center gap-3">
            <div class="w-10 h-10 rounded-lg bg-blue-500/20 flex items-center justify-center">
              <Clock class="w-5 h-5 text-blue-400" />
            </div>
            <div>
              <p class="text-sm text-slate-400">总任务数</p>
              <p class="text-xl font-bold text-white">{{ jobs.length }}</p>
            </div>
          </div>
        </div>
        <div class="bg-slate-800 rounded-lg p-4">
          <div class="flex items-center gap-3">
            <div class="w-10 h-10 rounded-lg bg-emerald-500/20 flex items-center justify-center">
              <Check class="w-5 h-5 text-emerald-400" />
            </div>
            <div>
              <p class="text-sm text-slate-400">已启用</p>
              <p class="text-xl font-bold text-white">{{ enabledCount }}</p>
            </div>
          </div>
        </div>
        <div class="bg-slate-800 rounded-lg p-4">
          <div class="flex items-center gap-3">
            <div class="w-10 h-10 rounded-lg bg-amber-500/20 flex items-center justify-center">
              <Pause class="w-5 h-5 text-amber-400" />
            </div>
            <div>
              <p class="text-sm text-slate-400">已禁用</p>
              <p class="text-xl font-bold text-white">{{ jobs.length - enabledCount }}</p>
            </div>
          </div>
        </div>
      </div>

      <!-- Loading -->
      <div v-if="loading" class="flex items-center justify-center py-20">
        <Loader2 class="w-8 h-8 text-blue-500 animate-spin" />
      </div>

      <!-- Empty State -->
      <div v-else-if="jobs.length === 0" class="text-center py-20">
        <Clock class="w-16 h-16 mx-auto text-slate-600 mb-4" />
        <h3 class="text-lg font-medium text-white mb-2">暂无计划任务</h3>
        <p class="text-slate-400 mb-4">点击上方按钮添加您的第一个计划任务</p>
      </div>

      <!-- Job List -->
      <div v-else class="space-y-3">
        <div
          v-for="job in jobs"
          :key="job.id"
          class="bg-slate-800 rounded-xl p-4"
          :class="{ 'opacity-60': !job.enabled }"
        >
          <div class="flex items-start justify-between gap-4">
            <div class="flex-1 min-w-0">
              <div class="flex items-center gap-3 mb-2">
                <span
                  class="px-2 py-1 rounded text-xs font-medium"
                  :class="job.enabled ? 'bg-emerald-500/20 text-emerald-400' : 'bg-slate-700 text-slate-400'"
                >
                  {{ job.enabled ? '已启用' : '已禁用' }}
                </span>
                <span class="text-slate-400 text-sm">{{ job.schedule }}</span>
                <code class="text-xs text-slate-500 bg-slate-700 px-2 py-0.5 rounded">
                  {{ job.minute }} {{ job.hour }} {{ job.day }} {{ job.month }} {{ job.weekday }}
                </code>
              </div>
              <div class="flex items-center gap-2 mb-1">
                <Terminal class="w-4 h-4 text-slate-500" />
                <code class="text-sm text-white font-mono break-all">{{ job.command }}</code>
              </div>
              <p class="text-xs text-slate-500">执行用户: {{ job.user }}</p>
            </div>
            <div class="flex items-center gap-2">
              <button
                @click="runNow(job)"
                class="p-2 rounded-lg bg-emerald-600/20 hover:bg-emerald-600 text-emerald-400 hover:text-white transition"
                title="立即执行"
              >
                <Play class="w-4 h-4" />
              </button>
              <button
                @click="toggleJob(job)"
                :disabled="!!actionLoading"
                class="p-2 rounded-lg transition"
                :class="job.enabled ? 'bg-amber-600/20 hover:bg-amber-600 text-amber-400 hover:text-white' : 'bg-emerald-600/20 hover:bg-emerald-600 text-emerald-400 hover:text-white'"
                :title="job.enabled ? '禁用' : '启用'"
              >
                <Loader2 v-if="actionLoading === `toggle-${job.id}`" class="w-4 h-4 animate-spin" />
                <Pause v-else-if="job.enabled" class="w-4 h-4" />
                <Play v-else class="w-4 h-4" />
              </button>
              <button
                @click="openEditModal(job)"
                class="p-2 rounded-lg bg-slate-700 hover:bg-slate-600 text-slate-400 hover:text-white transition"
                title="编辑"
              >
                <Edit2 class="w-4 h-4" />
              </button>
              <button
                @click="deleteJob(job)"
                :disabled="!!actionLoading"
                class="p-2 rounded-lg bg-red-600/20 hover:bg-red-600 text-red-400 hover:text-white transition"
                title="删除"
              >
                <Loader2 v-if="actionLoading === `delete-${job.id}`" class="w-4 h-4 animate-spin" />
                <Trash2 v-else class="w-4 h-4" />
              </button>
            </div>
          </div>
        </div>
      </div>
    </div>

    <!-- Create/Edit Modal -->
    <Teleport to="body">
      <div v-if="showModal" class="fixed inset-0 z-50 flex items-center justify-center p-4">
        <div class="absolute inset-0 bg-black/60 backdrop-blur-sm" @click="showModal = false"></div>
        <div class="relative bg-slate-800 rounded-xl w-full max-w-lg">
          <div class="px-6 py-4 border-b border-slate-700 flex items-center justify-between">
            <h3 class="text-lg font-semibold text-white">
              {{ editingJob ? '编辑任务' : '添加任务' }}
            </h3>
            <button @click="showModal = false" class="text-slate-400 hover:text-white">
              <X class="w-5 h-5" />
            </button>
          </div>

          <div class="p-6 space-y-4">
            <!-- Presets -->
            <div>
              <label class="block text-sm text-slate-400 mb-2">快速设置</label>
              <div class="flex flex-wrap gap-2">
                <button
                  v-for="preset in presets"
                  :key="preset.label"
                  @click="applyPreset(preset)"
                  class="px-3 py-1.5 text-xs rounded-lg bg-slate-700 hover:bg-slate-600 text-slate-300 transition"
                >
                  {{ preset.label }}
                </button>
              </div>
            </div>

            <!-- Time Fields -->
            <div class="grid grid-cols-5 gap-3">
              <div>
                <label class="block text-xs text-slate-400 mb-1">分钟</label>
                <input
                  v-model="form.minute"
                  class="w-full bg-slate-700 text-white rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500"
                  placeholder="*"
                />
              </div>
              <div>
                <label class="block text-xs text-slate-400 mb-1">小时</label>
                <input
                  v-model="form.hour"
                  class="w-full bg-slate-700 text-white rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500"
                  placeholder="*"
                />
              </div>
              <div>
                <label class="block text-xs text-slate-400 mb-1">日</label>
                <input
                  v-model="form.day"
                  class="w-full bg-slate-700 text-white rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500"
                  placeholder="*"
                />
              </div>
              <div>
                <label class="block text-xs text-slate-400 mb-1">月</label>
                <input
                  v-model="form.month"
                  class="w-full bg-slate-700 text-white rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500"
                  placeholder="*"
                />
              </div>
              <div>
                <label class="block text-xs text-slate-400 mb-1">周</label>
                <input
                  v-model="form.weekday"
                  class="w-full bg-slate-700 text-white rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500"
                  placeholder="*"
                />
              </div>
            </div>

            <!-- Preview -->
            <div class="bg-slate-900 rounded-lg p-3">
              <p class="text-xs text-slate-400 mb-1">Cron 表达式预览</p>
              <code class="text-sm text-blue-400 font-mono">{{ cronExpression }}</code>
            </div>

            <!-- User -->
            <div>
              <label class="block text-sm text-slate-400 mb-2">执行用户</label>
              <input
                v-model="form.user"
                class="w-full bg-slate-700 text-white rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500"
                placeholder="root"
              />
            </div>

            <!-- Command -->
            <div>
              <label class="block text-sm text-slate-400 mb-2">执行命令</label>
              <textarea
                v-model="form.command"
                rows="3"
                class="w-full bg-slate-700 text-white rounded-lg px-3 py-2 text-sm font-mono focus:outline-none focus:ring-2 focus:ring-blue-500 resize-none"
                placeholder="/usr/bin/php /path/to/script.php"
              ></textarea>
            </div>

            <!-- Warning -->
            <div class="flex items-start gap-2 p-3 bg-amber-500/10 border border-amber-500/20 rounded-lg">
              <AlertTriangle class="w-4 h-4 text-amber-400 mt-0.5" />
              <p class="text-xs text-amber-300">
                计划任务将写入 /etc/crontab 文件。请确保命令正确，错误的命令可能影响系统运行。
              </p>
            </div>
          </div>

          <div class="px-6 py-4 border-t border-slate-700 flex justify-end gap-3">
            <button
              @click="showModal = false"
              class="px-4 py-2 rounded-lg bg-slate-700 hover:bg-slate-600 text-white transition"
            >
              取消
            </button>
            <button
              @click="saveJob"
              :disabled="!!actionLoading"
              class="px-4 py-2 rounded-lg bg-blue-600 hover:bg-blue-700 text-white transition flex items-center gap-2"
            >
              <Loader2 v-if="actionLoading === 'save'" class="w-4 h-4 animate-spin" />
              {{ editingJob ? '保存' : '创建' }}
            </button>
          </div>
        </div>
      </div>
    </Teleport>

    <!-- Run Output Modal -->
    <Teleport to="body">
      <div v-if="showRunModal" class="fixed inset-0 z-50 flex items-center justify-center p-4">
        <div class="absolute inset-0 bg-black/60 backdrop-blur-sm" @click="showRunModal = false"></div>
        <div class="relative bg-slate-800 rounded-xl w-full max-w-2xl max-h-[80vh] flex flex-col">
          <div class="px-6 py-4 border-b border-slate-700 flex items-center justify-between">
            <h3 class="text-lg font-semibold text-white">执行结果</h3>
            <button @click="showRunModal = false" class="text-slate-400 hover:text-white">
              <X class="w-5 h-5" />
            </button>
          </div>
          <div class="p-4 overflow-auto flex-1">
            <div v-if="runLoading" class="flex items-center justify-center py-8">
              <Loader2 class="w-6 h-6 text-blue-500 animate-spin" />
              <span class="ml-2 text-slate-400">正在执行...</span>
            </div>
            <pre v-else class="text-xs font-mono text-slate-300 whitespace-pre-wrap">{{ runOutput }}</pre>
          </div>
        </div>
      </div>
    </Teleport>
  </Layout>
</template>
