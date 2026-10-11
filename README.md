int project

## Desenvolvimento

As ferramentas (Rojo, selene, StyLua) estão fixadas em `rokit.toml`. Com o [Rokit](https://github.com/rojo-rbx/rokit) instalado:

```bash
rokit install                                  # instala as versões do projeto
stylua src                                     # formata o código
stylua --check src                             # só verifica a formatação (como no CI)
selene src                                     # lint (std = roblox)
rojo build default.project.json -o xoblor.rbxl # gera o place
rojo serve default.project.json                # sincroniza com o Studio
```

Sem Rokit, `./setup.sh [serve|build]` baixa só o Rojo.

## CI e release

- **CI** (`.github/workflows/ci.yml`): em push e PR para `main`, roda StyLua, selene e o build com Rojo; o `xoblor.rbxl` fica como artefato da execução.
- **CodeQL** (`codeql.yml`): analisa a segurança dos workflows do GitHub Actions.
- **Dependabot**: atualiza as actions semanalmente.
- **Release**: crie e envie uma tag para gerar a GitHub Release com o `xoblor.rbxl` anexado:

```bash
git tag v0.1.0
git push origin v0.1.0
```
