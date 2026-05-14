# file.lazydeck

本地文件浏览插件。

## 功能

- 进入 `/file` 后直接从文件系统根目录 `/` 开始浏览
- 列表区域会在文件和目录名前显示图标；目录名仍显示为蓝色，文件名显示为白色
- hover 文件时，底部左侧会显示该文件大小，样式为白底蓝字的 ` 608K `
- 目录项通过 entry metatable 提供局部 `keymap`，支持用右键/回车进入
- 文件项不会继续被当作目录进入，右键/回车只会刷新预览
- `n`：在当前目录创建新文件，创建成功后会自动 hover 到新文件
- `N`：在当前目录创建新文件夹，创建成功后会自动 hover 到新文件夹
- `e`：通过 `deck.system.edit` 用外部编辑器编辑当前文件（优先 `$VISUAL`，其次 `$EDITOR`，默认 `vi`）
- `r`：重命名当前文件或目录
- `Space`：切换当前 hovered 条目的选中状态，并在刷新后自动下移一项；选中标记显示为彩色 `▌`
- `.`：切换是否显示隐藏文件
- `yy`：如果存在已选条目，则只复制所有已选条目；否则复制当前 hovered 的文件或目录，并注册一次性的 `p`。复制后源条目标记变为绿底，粘贴成功后清除
- `xx`：如果存在已选条目，则剪切所有已选条目；否则剪切当前 hovered 的文件或目录，并注册一次性的 `p`。剪切后源条目标记变为红底，粘贴成功后清除
- `dd`：如果存在已选条目，则删除所有已选条目；否则删除当前 hovered 的文件或目录
- `p`：在当前 `/file/...` 目录中粘贴刚才复制的文件或目录
- 预览区域：
  - 目录：展示子文件列表
  - 常见代码文件：异步读取后使用 `deck.style.highlight` 语法高亮
  - 其他文本文件：纯文本展示
  - 文件预览只加载配置的最大字符数，不会在向下滚动时继续读取更多内容

## 配置

在 `~/.config/lazydeck/init.lua` 中加入：

```lua
{
  dir = 'plugins/file.lazydeck',
  config = function()
    require('file').setup()
  end,
},
```

可选配置：

```lua
require('file').setup {
  preview_max_chars = 60000,
  show_hidden = false,
  keymap = {
    open = '<right>',
    enter = '<enter>',
    new_file = 'n',
    new_dir = 'N',
    select = '<space>',
    toggle_hidden = '.',
    yank = 'yy',
    cut = 'xx',
    delete = 'dd',
    paste = 'p',
  },
}
```

## 结构

- `file/init.lua`: 无状态工厂入口，同时兼容本地 `/file` 默认实例
- `file/browser.lua`: 通用文件浏览器实例，负责列表构建和 entry 组装
- `file/actions.lua`: 基于 browser/provider 实例的复制、粘贴、删除、创建等动作
- `file/config.lua`: browser 实例配置构建
- `file/metas.lua`: 给 entry 注入实例级 `keymap` 和 `preview`
- `file/preview.lua`: 通用目录/文件预览渲染
- `file/icons.lua`: 图标匹配封装，复用 vendored 的 nvim-web-devicons 扩展名映射
- `file/icons_by_file_extension.lua`: 从 nvim-web-devicons 复制的扩展名图标和颜色表
- `file/provider/local.lua`: 本地文件系统 provider，实现读写、路径编解码，并在 handle 上提供 `size`

## 复用

`require('file')` 现在既可以作为本地文件插件使用，也可以作为其他文件系统浏览插件的浏览器工厂：

```lua
local file = require 'file'
local browser = file.new(my_provider, {
  preview_max_chars = 60000,
})
```

对外可复用的工厂函数：

- `file.new(provider, opt)`: 使用自定义 provider 创建一个独立 browser 实例
- `file.new_local(opt)`: 使用本地文件系统 provider 创建 browser 实例
- `file.get_icon(target, opt)`: 根据文件名、路径或 handle 获取图标、颜色和图标元数据

每个 browser 实例独立维护自己的选中态、剪贴板态、隐藏文件开关和预览 token，适合在 `sftp`、`adb`、`docker` 等插件中按 profile、设备、容器分别持有多个实例。

provider 需要实现一组面向 callback 的方法，便于对接异步命令型后端；其中 `list()` 返回的 handle 可以携带 `size` 等元信息，供 browser 渲染底部状态行：

- `decode_page_path(path)` / `encode_page_path(handle)`
- `parent(handle)` / `join(dir_handle, name)`
- `list(dir_handle, cb)`
- `stat(handle, cb)`
- `read_file(handle, opts, cb)`
- `create_file(dir_handle, name, cb)` / `create_dir(dir_handle, name, cb)`
- `remove(handles, cb)`
- `copy(handles, target_dir, cb)` / `move(handles, target_dir, cb)`
