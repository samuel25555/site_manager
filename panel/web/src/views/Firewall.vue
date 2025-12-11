<script setup lang="ts">
import { ref, onMounted } from "vue"
import { api } from "../stores/auth"
import Layout from "../components/Layout.vue"
import { Shield, Plus, Trash2, Power, PowerOff, RefreshCw } from "lucide-vue-next"

interface Rule {
  number: number
  to: string
  action: string
  from: string
  port: string
  protocol: string
  comment: string
}

const enabled = ref(false)
const rules = ref<Rule[]>([])
const loading = ref(true)
const actionLoading = ref(false)

const showAddDialog = ref(false)
const newPort = ref("")
const newProtocol = ref("tcp")
const newComment = ref("")

async function loadStatus() {
  loading.value = true
  try {
    const res = await api.get("/firewall/status")
    if (res.data.status) {
      enabled.value = res.data.data.enabled
      rules.value = res.data.data.rules || []
    }
  } catch (e: any) {
    console.error(e)
  } finally {
    loading.value = false
  }
}

async function toggleFirewall() {
  actionLoading.value = true
  try {
    const endpoint = enabled.value ? "/firewall/disable" : "/firewall/enable"
    const res = await api.post(endpoint)
    if (res.data.status) {
      await loadStatus()
    } else {
      alert(res.data.error || "操作失败")
    }
  } catch (e: any) {
    alert(e.response?.data?.error || "操作失败")
  } finally {
    actionLoading.value = false
  }
}

async function addRule() {
  if (!newPort.value) return
  actionLoading.value = true
  try {
    const res = await api.post("/firewall/allow", {
      port: parseInt(newPort.value),
      protocol: newProtocol.value,
      comment: newComment.value
    })
    if (res.data.status) {
      showAddDialog.value = false
      newPort.value = ""
      newComment.value = ""
      await loadStatus()
    } else {
      alert(res.data.error || "添加失败")
    }
  } catch (e: any) {
    alert(e.response?.data?.error || "添加失败")
  } finally {
    actionLoading.value = false
  }
}

async function deleteRule(number: number) {
  if (!confirm("确定删除此规则?")) return
  actionLoading.value = true
  try {
    const res = await api.delete("/firewall/rule/" + number)
    if (res.data.status) {
      await loadStatus()
    } else {
      alert(res.data.error || "删除失败")
    }
  } catch (e: any) {
    alert(e.response?.data?.error || "删除失败")
  } finally {
    actionLoading.value = false
  }
}

onMounted(loadStatus)
</script>

<template>
  <Layout>
    <div class="p-6">
      <!-- 标题栏 -->
      <div class="flex justify-between items-center mb-6">
        <div class="flex items-center gap-3">
          <Shield class="w-8 h-8 text-blue-400" />
          <div>
            <h1 class="text-2xl font-bold text-white">防火墙管理</h1>
            <p class="text-slate-400 text-sm">管理服务器防火墙规则 (UFW)</p>
          </div>
        </div>
        <div class="flex gap-2">
          <button @click="loadStatus" :disabled="loading" class="btn-secondary">
            <RefreshCw :class="['w-4 h-4', loading && 'animate-spin']" />
            刷新
          </button>
        </div>
      </div>

      <!-- 状态卡片 -->
      <div class="bg-slate-800 rounded-lg p-6 mb-6">
        <div class="flex items-center justify-between">
          <div class="flex items-center gap-4">
            <div :class="['w-16 h-16 rounded-full flex items-center justify-center', enabled ? 'bg-green-500/20' : 'bg-red-500/20']">
              <Power v-if="enabled" class="w-8 h-8 text-green-400" />
              <PowerOff v-else class="w-8 h-8 text-red-400" />
            </div>
            <div>
              <h2 class="text-xl font-semibold text-white">防火墙状态</h2>
              <p :class="enabled ? 'text-green-400' : 'text-red-400'">
                {{ enabled ? '已开启' : '已关闭' }}
              </p>
            </div>
          </div>
          <button 
            @click="toggleFirewall" 
            :disabled="actionLoading"
            :class="enabled ? 'bg-red-600 hover:bg-red-700' : 'bg-green-600 hover:bg-green-700'"
            class="px-6 py-2 text-white rounded-lg transition flex items-center gap-2"
          >
            <PowerOff v-if="enabled" class="w-4 h-4" />
            <Power v-else class="w-4 h-4" />
            {{ enabled ? '关闭防火墙' : '开启防火墙' }}
          </button>
        </div>
      </div>

      <!-- 规则列表 -->
      <div class="bg-slate-800 rounded-lg overflow-hidden">
        <div class="px-6 py-4 border-b border-slate-700 flex items-center justify-between">
          <h3 class="text-lg font-semibold text-white">防火墙规则</h3>
          <button @click="showAddDialog = true" class="btn-primary flex items-center gap-2">
            <Plus class="w-4 h-4" />
            添加规则
          </button>
        </div>

        <div v-if="loading" class="p-8 text-center text-slate-400">
          加载中...
        </div>
        <div v-else-if="rules.length === 0" class="p-8 text-center text-slate-400">
          暂无规则
        </div>
        <table v-else class="w-full">
          <thead class="bg-slate-700">
            <tr>
              <th class="p-3 text-left text-slate-300 w-16">#</th>
              <th class="p-3 text-left text-slate-300">端口</th>
              <th class="p-3 text-left text-slate-300">协议</th>
              <th class="p-3 text-left text-slate-300">动作</th>
              <th class="p-3 text-left text-slate-300">来源</th>
              <th class="p-3 text-left text-slate-300">备注</th>
              <th class="p-3 text-left text-slate-300 w-20">操作</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="rule in rules" :key="rule.number" class="border-t border-slate-700 hover:bg-slate-700/50">
              <td class="p-3 text-slate-400">{{ rule.number }}</td>
              <td class="p-3 text-white font-mono">{{ rule.port || rule.to }}</td>
              <td class="p-3 text-slate-400 uppercase">{{ rule.protocol || '-' }}</td>
              <td class="p-3">
                <span :class="rule.action === 'ALLOW' ? 'text-green-400' : 'text-red-400'">
                  {{ rule.action }}
                </span>
              </td>
              <td class="p-3 text-slate-400">{{ rule.from }}</td>
              <td class="p-3 text-slate-400">{{ rule.comment || '-' }}</td>
              <td class="p-3">
                <button @click="deleteRule(rule.number)" class="p-1.5 rounded hover:bg-red-600/20 text-red-400" title="删除">
                  <Trash2 class="w-4 h-4" />
                </button>
              </td>
            </tr>
          </tbody>
        </table>
      </div>

      <!-- 添加规则弹窗 -->
      <div v-if="showAddDialog" class="fixed inset-0 bg-black/50 flex items-center justify-center z-50">
        <div class="bg-slate-800 rounded-lg p-6 w-96">
          <h3 class="text-white font-semibold mb-4 flex items-center gap-2">
            <Plus class="w-5 h-5" />
            添加防火墙规则
          </h3>
          <div class="space-y-4">
            <div>
              <label class="block text-slate-400 text-sm mb-1">端口号</label>
              <input 
                v-model="newPort" 
                type="number" 
                placeholder="如: 3306" 
                class="w-full p-2 bg-slate-700 text-white rounded outline-none focus:ring-2 focus:ring-blue-500"
              />
            </div>
            <div>
              <label class="block text-slate-400 text-sm mb-1">协议</label>
              <select v-model="newProtocol" class="w-full p-2 bg-slate-700 text-white rounded outline-none">
                <option value="tcp">TCP</option>
                <option value="udp">UDP</option>
              </select>
            </div>
            <div>
              <label class="block text-slate-400 text-sm mb-1">备注 (可选)</label>
              <input 
                v-model="newComment" 
                placeholder="如: MySQL" 
                class="w-full p-2 bg-slate-700 text-white rounded outline-none focus:ring-2 focus:ring-blue-500"
              />
            </div>
          </div>
          <div class="flex justify-end gap-2 mt-6">
            <button @click="showAddDialog = false" class="btn-secondary">取消</button>
            <button @click="addRule" :disabled="actionLoading" class="btn-primary">添加</button>
          </div>
        </div>
      </div>
    </div>
  </Layout>
</template>

<style scoped>
.btn-primary { @apply px-4 py-2 bg-blue-600 hover:bg-blue-700 text-white rounded-lg text-sm transition; }
.btn-secondary { @apply px-4 py-2 bg-slate-700 hover:bg-slate-600 text-white rounded-lg text-sm transition flex items-center gap-2; }
</style>
