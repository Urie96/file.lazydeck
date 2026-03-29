# file.lazycmd

本地文件浏览插件。

## 功能

- 进入 `/file` 后直接从文件系统根目录 `/` 开始浏览
- 列表区域目录显示为蓝色，文件显示为白色
- 目录项通过 entry metatable 提供局部 `keymap`，支持用右键/回车进入
- 文件项不会继续被当作目录进入，右键/回车只会刷新预览
- `n`：在当前目录创建新文件
- `N`：在当前目录创建新文件夹
- `Space`：切换当前 hovered 条目的选中状态，并自动移动到下一个条目；选中标记显示为黄底单字符
- `.`：切换是否显示隐藏文件
- `yy`：如果存在已选条目，则只复制所有已选条目；否则复制当前 hovered 的文件或目录，并注册一次性的 `p`。复制后源条目标记变为绿底，粘贴成功后清除
- `xx`：如果存在已选条目，则剪切所有已选条目；否则剪切当前 hovered 的文件或目录，并注册一次性的 `p`。剪切后源条目标记变为红底，粘贴成功后清除
- `dd`：如果存在已选条目，则删除所有已选条目；否则删除当前 hovered 的文件或目录
- `p`：在当前 `/file/...` 目录中粘贴刚才复制的文件或目录
- 预览区域：
  - 目录：展示子文件列表
  - 常见代码文件：异步读取后使用 `lc.style.highlight` 语法高亮
  - 其他文本文件：纯文本展示
  - 文件预览只加载配置的最大字符数，不会在向下滚动时继续读取更多内容

## 配置

在 `~/.config/lazycmd/init.lua` 中加入：

```lua
{
  dir = 'plugins/file.lazycmd',
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

- `file/init.lua`: 列表构建、路径处理、插件入口
- `file/actions.lua`: 复制/粘贴动作与一次性 keymap 注册
- `file/config.lua`: 配置读取与默认键位
- `file/metas.lua`: 通过 metatable 注入 entry 级 `keymap` 和 `preview`
- `file/preview.lua`: 目录/文件预览渲染
