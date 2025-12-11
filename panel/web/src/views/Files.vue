<script setup lang="ts">
import { ref, computed, onMounted, watch } from "vue"
import { api } from "../stores/auth"
import Layout from "../components/Layout.vue"
import { FolderOpen, RefreshCw, Plus, Upload, Trash2, Download, Edit, ChevronRight } from "lucide-vue-next"

interface FileItem {
  name: string
  path: string
  size: number
  mode: string
  mod_time: string
  is_dir: boolean
  is_symlink: boolean
  link_target?: string
}

const currentPath = ref("/www")
const files = ref<FileItem[]>([])
const parent = ref("")
const loading = ref(false)
const showHidden = ref(false)
const selectedFiles = ref<Set<string>>(new Set())

const editingFile = ref<string | null>(null)
const editContent = ref("")
const editLoading = ref(false)

const showCreateDialog = ref(false)
const newItemName = ref("")
const newItemIsDir = ref(false)

const showRenameDialog = ref(false)
const renameTarget = ref<FileItem | null>(null)
const newName = ref("")

const showUploadDialog = ref(false)
const uploadFiles = ref<FileList | null>(null)

async function loadFiles() {
  loading.value = true
  try {
    const res = await api.get("/files/list", {
      params: { path: currentPath.value, show_hidden: showHidden.value }
    })
    if (res.data.status) {
      files.value = res.data.data.files || []
      parent.value = res.data.data.parent
      currentPath.value = res.data.data.path
    }
  } catch (e: any) {
    alert(e.response?.data?.error || "加载失败")
  } finally {
    loading.value = false
  }
  selectedFiles.value.clear()
}

function navigateTo(path: string) {
  currentPath.value = path
  loadFiles()
}

function goUp() {
  if (parent.value) navigateTo(parent.value)
}

function openItem(item: FileItem) {
  if (item.is_dir) {
    navigateTo(item.path)
  } else {
    editFile(item)
  }
}

const breadcrumbs = computed(() => {
  const parts = currentPath.value.split("/").filter(Boolean)
  const crumbs = [{ name: "/", path: "/" }]
  let path = ""
  for (const part of parts) {
    path += "/" + part
    crumbs.push({ name: part, path })
  }
  return crumbs
})

function formatSize(bytes: number): string {
  if (bytes === 0) return "-"
  const units = ["B", "KB", "MB", "GB"]
  let i = 0
  while (bytes >= 1024 && i < units.length - 1) {
    bytes /= 1024
    i++
  }
  return bytes.toFixed(i > 0 ? 1 : 0) + " " + units[i]
}

function formatTime(time: string): string {
  return new Date(time).toLocaleString()
}

function getIcon(item: FileItem): string {
  if (item.is_dir) return "📁"
  if (item.is_symlink) return "🔗"
  const ext = item.name.split(".").pop()?.toLowerCase()
  const icons: Record<string, string> = {
    js: "📜", ts: "📜", vue: "💚", php: "🐘", py: "🐍",
    html: "🌐", css: "🎨", json: "📋", md: "📝",
    jpg: "🖼️", png: "🖼️", gif: "🖼️", svg: "🖼️",
    zip: "📦", tar: "📦", gz: "📦",
    sh: "⚙️", conf: "⚙️", env: "🔐",
  }
  return icons[ext || ""] || "📄"
}

async function editFile(item: FileItem) {
  editLoading.value = true
  try {
    const res = await api.get("/files/read", { params: { path: item.path } })
    if (res.data.status) {
      editingFile.value = item.path
      editContent.value = res.data.data.content
    }
  } catch (e: any) {
    alert(e.response?.data?.error || "无法读取文件")
  } finally {
    editLoading.value = false
  }
}

async function saveFile() {
  if (!editingFile.value) return
  editLoading.value = true
  try {
    await api.post("/files/save", { path: editingFile.value, content: editContent.value })
    alert("保存成功")
  } catch (e: any) {
    alert(e.response?.data?.error || "保存失败")
  } finally {
    editLoading.value = false
  }
}

function closeEditor() {
  editingFile.value = null
  editContent.value = ""
}

async function createItem() {
  if (!newItemName.value) return
  const basePath = currentPath.value.endsWith("/") ? currentPath.value.slice(0, -1) : currentPath.value
  const newPath = basePath + "/" + newItemName.value
  try {
    await api.post("/files/create", { path: newPath, is_dir: newItemIsDir.value })
    showCreateDialog.value = false
    newItemName.value = ""
    loadFiles()
  } catch (e: any) {
    alert(e.response?.data?.error || "创建失败")
  }
}

async function renameItem() {
  if (!renameTarget.value || !newName.value) return
  const dir = renameTarget.value.path.substring(0, renameTarget.value.path.lastIndexOf("/"))
  try {
    await api.post("/files/rename", { old_path: renameTarget.value.path, new_path: dir + "/" + newName.value })
    showRenameDialog.value = false
    renameTarget.value = null
    newName.value = ""
    loadFiles()
  } catch (e: any) {
    alert(e.response?.data?.error || "重命名失败")
  }
}

function startRename(item: FileItem) {
  renameTarget.value = item
  newName.value = item.name
  showRenameDialog.value = true
}

async function deleteSelected() {
  if (selectedFiles.value.size === 0) return
  if (!confirm("确定删除 " + selectedFiles.value.size + " 个项目?")) return
  try {
    await api.post("/files/delete", { paths: Array.from(selectedFiles.value) })
    loadFiles()
  } catch (e: any) {
    alert(e.response?.data?.error || "删除失败")
  }
}

async function uploadFile() {
  if (!uploadFiles.value?.length) return
  const formData = new FormData()
  formData.append("path", currentPath.value)
  for (const file of uploadFiles.value) {
    formData.append("files", file)
  }
  try {
    await api.post("/files/upload", formData)
    showUploadDialog.value = false
    uploadFiles.value = null
    loadFiles()
  } catch (e: any) {
    alert(e.response?.data?.error || "上传失败")
  }
}

function downloadFile(item: FileItem) {
  window.open("/api/files/download?path=" + encodeURIComponent(item.path), "_blank")
}

function toggleSelect(path: string) {
  if (selectedFiles.value.has(path)) {
    selectedFiles.value.delete(path)
  } else {
    selectedFiles.value.add(path)
  }
}

function selectAll() {
  if (selectedFiles.value.size === files.value.length) {
    selectedFiles.value.clear()
  } else {
    files.value.forEach(f => selectedFiles.value.add(f.path))
  }
}

onMounted(loadFiles)
watch(showHidden, loadFiles)
</script>

<template>
  <Layout>
    <div class="p-6">
      <!-- 标题 -->
      <div class="flex justify-between items-center mb-6">
        <div class="flex items-center gap-3">
          <FolderOpen class="w-8 h-8 text-blue-400" />
          <div>
            <h1 class="text-2xl font-bold text-white">文件管理器</h1>
            <p class="text-slate-400 text-sm">管理服务器文件</p>
          </div>
        </div>
        <label class="flex items-center text-slate-400 text-sm cursor-pointer">
          <input type="checkbox" v-model="showHidden" class="mr-2" />
          显示隐藏文件
        </label>
      </div>

      <!-- 工具栏 -->
      <div class="bg-slate-800 rounded-lg p-3 mb-4 flex gap-2 flex-wrap">
        <button @click="goUp" :disabled="!parent" class="btn-secondary" :class="{ 'opacity-50': !parent }">⬆️ 上级</button>
        <button @click="loadFiles" class="btn-secondary"><RefreshCw class="w-4 h-4" /> 刷新</button>
        <button @click="showCreateDialog = true; newItemIsDir = false" class="btn-primary"><Plus class="w-4 h-4" /> 新建文件</button>
        <button @click="showCreateDialog = true; newItemIsDir = true" class="btn-primary"><Plus class="w-4 h-4" /> 新建目录</button>
        <button @click="showUploadDialog = true" class="btn-primary"><Upload class="w-4 h-4" /> 上传</button>
        <button v-if="selectedFiles.size > 0" @click="deleteSelected" class="btn-danger"><Trash2 class="w-4 h-4" /> 删除 ({{ selectedFiles.size }})</button>
      </div>

      <!-- 面包屑 -->
      <div class="bg-slate-800 rounded-lg px-4 py-2 mb-4 flex items-center gap-1 overflow-x-auto">
        <template v-for="(crumb, i) in breadcrumbs" :key="crumb.path">
          <ChevronRight v-if="i > 0" class="w-4 h-4 text-slate-500" />
          <button @click="navigateTo(crumb.path)" class="text-blue-400 hover:text-blue-300 whitespace-nowrap px-1">{{ crumb.name }}</button>
        </template>
      </div>

      <!-- 文件列表 -->
      <div class="bg-slate-800 rounded-lg overflow-hidden">
        <table class="w-full">
          <thead class="bg-slate-700">
            <tr>
              <th class="p-3 text-left w-8"><input type="checkbox" @change="selectAll" :checked="selectedFiles.size === files.length && files.length > 0" /></th>
              <th class="p-3 text-left text-slate-300">名称</th>
              <th class="p-3 text-left text-slate-300 w-24">大小</th>
              <th class="p-3 text-left text-slate-300 w-32">权限</th>
              <th class="p-3 text-left text-slate-300 w-44">修改时间</th>
              <th class="p-3 text-left text-slate-300 w-24">操作</th>
            </tr>
          </thead>
          <tbody v-if="loading"><tr><td colspan="6" class="p-8 text-center text-slate-400">加载中...</td></tr></tbody>
          <tbody v-else-if="files.length === 0"><tr><td colspan="6" class="p-8 text-center text-slate-400">空目录</td></tr></tbody>
          <tbody v-else>
            <tr v-for="file in files" :key="file.path" class="border-t border-slate-700 hover:bg-slate-700/50" :class="{ 'bg-blue-900/20': selectedFiles.has(file.path) }">
              <td class="p-3"><input type="checkbox" :checked="selectedFiles.has(file.path)" @change="toggleSelect(file.path)" /></td>
              <td class="p-3">
                <button @click="openItem(file)" class="flex items-center gap-2 text-white hover:text-blue-400">
                  <span>{{ getIcon(file) }}</span>
                  <span>{{ file.name }}</span>
                  <span v-if="file.is_symlink" class="text-slate-500 text-sm">→ {{ file.link_target }}</span>
                </button>
              </td>
              <td class="p-3 text-slate-400">{{ file.is_dir ? "-" : formatSize(file.size) }}</td>
              <td class="p-3 text-slate-400 font-mono text-sm">{{ file.mode }}</td>
              <td class="p-3 text-slate-400 text-sm">{{ formatTime(file.mod_time) }}</td>
              <td class="p-3">
                <div class="flex gap-2">
                  <button @click="startRename(file)" class="text-slate-400 hover:text-white" title="重命名"><Edit class="w-4 h-4" /></button>
                  <button v-if="!file.is_dir" @click="downloadFile(file)" class="text-slate-400 hover:text-white" title="下载"><Download class="w-4 h-4" /></button>
                </div>
              </td>
            </tr>
          </tbody>
        </table>
      </div>

      <!-- 编辑器弹窗 -->
      <div v-if="editingFile" class="fixed inset-0 bg-black/80 flex items-center justify-center z-50 p-4">
        <div class="bg-slate-800 rounded-lg w-full max-w-5xl max-h-[90vh] flex flex-col">
          <div class="p-4 border-b border-slate-700 flex justify-between items-center">
            <h3 class="text-white font-semibold truncate">{{ editingFile }}</h3>
            <div class="flex gap-2">
              <button @click="saveFile" :disabled="editLoading" class="btn-primary">💾 保存</button>
              <button @click="closeEditor" class="btn-secondary">✕</button>
            </div>
          </div>
          <textarea v-model="editContent" class="flex-1 p-4 bg-slate-900 text-slate-100 font-mono text-sm resize-none outline-none min-h-[400px]" :disabled="editLoading"></textarea>
        </div>
      </div>

      <!-- 创建弹窗 -->
      <div v-if="showCreateDialog" class="fixed inset-0 bg-black/50 flex items-center justify-center z-50">
        <div class="bg-slate-800 rounded-lg p-6 w-96">
          <h3 class="text-white font-semibold mb-4">{{ newItemIsDir ? "新建目录" : "新建文件" }}</h3>
          <input v-model="newItemName" placeholder="输入名称" class="w-full p-2 bg-slate-700 text-white rounded mb-4 outline-none" @keyup.enter="createItem" />
          <div class="flex justify-end gap-2">
            <button @click="showCreateDialog = false" class="btn-secondary">取消</button>
            <button @click="createItem" class="btn-primary">创建</button>
          </div>
        </div>
      </div>

      <!-- 重命名弹窗 -->
      <div v-if="showRenameDialog" class="fixed inset-0 bg-black/50 flex items-center justify-center z-50">
        <div class="bg-slate-800 rounded-lg p-6 w-96">
          <h3 class="text-white font-semibold mb-4">重命名</h3>
          <input v-model="newName" class="w-full p-2 bg-slate-700 text-white rounded mb-4 outline-none" @keyup.enter="renameItem" />
          <div class="flex justify-end gap-2">
            <button @click="showRenameDialog = false" class="btn-secondary">取消</button>
            <button @click="renameItem" class="btn-primary">确定</button>
          </div>
        </div>
      </div>

      <!-- 上传弹窗 -->
      <div v-if="showUploadDialog" class="fixed inset-0 bg-black/50 flex items-center justify-center z-50">
        <div class="bg-slate-800 rounded-lg p-6 w-96">
          <h3 class="text-white font-semibold mb-4">上传文件</h3>
          <input type="file" multiple @change="e => uploadFiles = (e.target as HTMLInputElement).files" class="w-full p-2 bg-slate-700 text-white rounded mb-4" />
          <div class="flex justify-end gap-2">
            <button @click="showUploadDialog = false" class="btn-secondary">取消</button>
            <button @click="uploadFile" class="btn-primary">上传</button>
          </div>
        </div>
      </div>
    </div>
  </Layout>
</template>

<style scoped>
.btn-primary { @apply px-3 py-1.5 bg-blue-600 hover:bg-blue-700 text-white rounded text-sm transition flex items-center gap-1; }
.btn-secondary { @apply px-3 py-1.5 bg-slate-700 hover:bg-slate-600 text-white rounded text-sm transition flex items-center gap-1; }
.btn-danger { @apply px-3 py-1.5 bg-red-600 hover:bg-red-700 text-white rounded text-sm transition flex items-center gap-1; }
</style>
