# wezterm-setup

Kit de personalización para [WezTerm](https://wezfurlong.org/wezterm/) con tabs coloreados, iconos emoji y keybindings útiles.

## Qué incluye

- **`config/wezterm.lua`** — Configuración de WezTerm: tab bar con colores por pestaña, keybindings para panes/tabs, y navegación por palabras con Alt+flechas.
- **`bin/wez-tab`** — Herramienta CLI para asignar color, icono y título a la pestaña activa. Incluye autocompletado para zsh y bash.

## Instalación

```bash
git clone <repo-url> wezterm-setup
cd wezterm-setup
./setup.sh
```

## Uso rápido

```bash
wez-tab blue docker "compose up"   # 🐳 compose up (pestaña azul)
wez-tab red "my task"              # my task (pestaña roja, sin icono)
wez-tab green git rebase           # 🔀 rebase (pestaña verde)
```

## Colores disponibles

`red` · `orange` · `yellow` · `green` · `teal` · `cyan` · `blue` · `navy` · `purple` · `pink`

## Iconos

| Categoría | Iconos disponibles |
|---|---|
| Languages | `node` 💚  `python` 🐍  `rust` 🦀  `go` 🐹 |
| DevOps | `docker` 🐳  `k8s` ☸️  `server` 🖥️  `db` 🗄️  `ssh` 🔐  `deploy` 🚀  `monitor` 📊  `cloud` ☁️  `network` 🌐 |
| Workflow | `git` 🔀  `build` 🔨  `test` 🧪  `debug` 🐛  `edit` ✏️  `log` 📋  `shell` 🐚  `config` ⚙️  `search` 🔍  `clean` 🧹  `tools` 🔧 |
| Data | `api` 📡  `data` 📦  `download` ⬇️  `upload` ⬆️  `sync` 🔄 |
| Concepts | `security` 🔒  `docs` 📝  `ai` 🧠  `fire` 🔥  `alert` ⚠️ |
| Misc | `mail` 📧  `chat` 💬  `home` 🏠  `music` 🎵  `game` 🎮 |

Si el segundo argumento no coincide con un icono, se trata como parte del título.

## Shortcuts

```bash
wez-tab keys    # Muestra todos los keybindings categorizados
```

## Desinstalar

```bash
./setup.sh --uninstall
```

## Licencia

MIT
