# Python 环境架构

Site Manager 采用类似宝塔面板的 Python 环境架构，分为系统级和项目级两层。

## 架构概览

```
/opt/site_manager/
├── pyenv/                    # 系统级 Python 环境（管理工具专用）
│   ├── bin/                  # Python 解释器和工具
│   ├── lib/                  # 已安装的包
│   └── requirements.txt      # 包列表
│
└── python_project/           # 项目级环境（用户 Python 应用）
    ├── <project_name>/       # 各项目的虚拟环境
    │   ├── .venv/            # 项目虚拟环境
    │   └── logs/             # 项目日志
    └── ...
```

## 1. 系统级环境 - pyenv

### 用途

- 为 Site Manager 管理工具本身提供 Python 运行环境
- 运行管理脚本、监控脚本、API 集成等
- 独立于系统 Python，避免依赖冲突

### 特点

- 使用 **uv** 管理，快速可靠
- 全局安装常用包（requests, loguru, psutil 等）
- 提供便捷命令：`site-python`, `site-pip`

### 安装

```bash
# 运行配置脚本
bash /opt/site_manager/scripts/setup_python_env.sh
```

### 使用

```bash
# 1. 直接运行 Python 脚本
site-python /path/to/script.py

# 2. 安装新包
site-pip install package_name

# 3. 查看已安装包
site-pip list

# 4. 激活环境（交互式使用）
source /opt/site_manager/pyenv/bin/activate
```

### 已安装的包

基础包：

- `requests` - HTTP 客户端
- `loguru` - 日志管理
- `psutil` - 系统监控
- `pyyaml` - YAML 解析
- `click` - CLI 工具框架
- `jinja2` - 模板引擎

扩展包（按需安装）：

```bash
# API 集成
site-pip install httpx aiohttp

# 数据处理
site-pip install pandas openpyxl

# 云服务 SDK
site-pip install boto3 aliyun-python-sdk-core

# 监控告警
site-pip install prometheus-client
```

## 2. 项目级环境 - python_project

### 用途

- 为用户创建的 Python Web 应用提供独立虚拟环境
- 每个项目有独立的依赖、日志、配置
- 类似宝塔面板的 Python 项目管理

### 结构

```
/opt/site_manager/python_project/
├── myapp/                    # 项目名称
│   ├── .venv/                # 项目虚拟环境
│   ├── logs/                 # 应用日志
│   ├── app.py                # 应用入口
│   ├── requirements.txt      # 项目依赖
│   └── gunicorn.conf.py      # Gunicorn 配置
└── ...
```

### 使用（未来功能）

```bash
# 创建 Python 项目站点
site create myapp.com python

# 将会自动：
# 1. 创建独立虚拟环境
# 2. 配置 Supervisor 进程管理
# 3. 配置 Nginx 反向代理
# 4. 提供日志管理
```

## 对比：系统级 vs 项目级

| 特性     | 系统级 (pyenv)            | 项目级 (python_project)                   |
| -------- | ------------------------- | ----------------------------------------- |
| **用途** | 管理工具本身              | 用户 Python 应用                          |
| **路径** | `/opt/site_manager/pyenv` | `/opt/site_manager/python_project/<name>` |
| **依赖** | 全局共享                  | 项目独立                                  |
| **命令** | `site-python`, `site-pip` | 项目内 `.venv/bin/python`                 |
| **数量** | 唯一                      | 多个（每个项目一个）                      |
| **管理** | uv                        | venv/virtualenv                           |

## 与宝塔面板的对比

### 宝塔面板

```
/www/server/panel/pyenv/          # 面板系统环境
/www/server/python_project/       # 用户项目环境
```

### Site Manager

```
/opt/site_manager/pyenv/          # 管理工具系统环境
/opt/site_manager/python_project/ # 用户项目环境
```

## 最佳实践

### 系统级环境

1. **不要直接修改系统 Python** - 始终使用 `site-python`
2. **避免安装太多包** - 只安装管理工具真正需要的
3. **定期更新** - 使用 `site-pip install --upgrade <package>` 更新包
4. **记录依赖** - 安装新包后运行 `site-pip freeze > /opt/site_manager/pyenv/requirements.txt`

### 项目级环境

1. **每个项目独立环境** - 不要共享虚拟环境
2. **使用 requirements.txt** - 明确记录项目依赖
3. **指定 Python 版本** - 创建环境时指定版本
4. **定期清理** - 删除不用的项目环境

## 故障排查

### 系统级环境问题

**问题：site-python 命令找不到**

```bash
# 重新创建符号链接
ln -sf /opt/site_manager/pyenv/bin/python /usr/local/bin/site-python
ln -sf /opt/site_manager/pyenv/bin/pip /usr/local/bin/site-pip
```

**问题：包安装失败**

```bash
# 更新 pip
site-pip install --upgrade pip

# 或重建环境
bash /opt/site_manager/scripts/setup_python_env.sh
```

**问题：Python 版本不对**

```bash
# 检查版本
site-python --version

# 重建环境（会提示是否删除旧环境）
bash /opt/site_manager/scripts/setup_python_env.sh
```

### 项目级环境问题

**问题：虚拟环境损坏**

```bash
# 删除并重建
rm -rf /opt/site_manager/python_project/myapp/.venv
python3 -m venv /opt/site_manager/python_project/myapp/.venv
source /opt/site_manager/python_project/myapp/.venv/bin/activate
pip install -r requirements.txt
```

## 扩展阅读

- [uv 文档](https://github.com/astral-sh/uv)
- [Python 虚拟环境最佳实践](https://docs.python.org/3/library/venv.html)
- [宝塔面板 Python 项目管理](https://www.bt.cn/)
