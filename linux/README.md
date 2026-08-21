# Lion Pass para Linux

Aplicação Linux do Lion Pass em .NET 8 e Avalonia, com o mesmo núcleo criptográfico das versões Windows e Apple.

Os builds oficiais desativam explicitamente a telemetria de compilação do Avalonia e do .NET.

## Distribuições

- Ubuntu 22.04 ou mais recente, Debian 12+ e Fedora 40+.
- Processadores x64 e ARM64.
- X11 ou Wayland por meio do XWayland.
- `libsecret-tools` é opcional e habilita o desbloqueio pelo chaveiro da sessão.

## Executar para desenvolvimento

```bash
dotnet run --project src/LionPass.App/LionPass.App.csproj
```

## Compilar

```bash
dotnet build src/LionPass.App/LionPass.App.csproj -c Release
dotnet test ../shared/dotnet/LionPass.Core.Tests/LionPass.Core.Tests.csproj -c Release
```

## Gerar pacotes

```bash
./scripts/build-packages.sh linux-x64
```

O script sempre gera uma distribuição portátil `.tar.gz`. Em Debian/Ubuntu também gera `.deb` quando `dpkg-deb` estiver disponível. Se `appimagetool` estiver instalado ou indicado pela variável `APPIMAGETOOL`, gera um AppImage.

## Armazenamento

O cofre padrão permanece em `~/.local/share/Lion Code Technology/Lion Pass/default.lionvault`. A chave opcional de desbloqueio é guardada pelo Secret Service do ambiente gráfico usando `secret-tool`; ela nunca é salva em texto simples nos arquivos de configuração.

## Compatibilidade

Arquivos `.lionvault` exportados pelo Linux podem ser abertos no macOS, iOS, iPadOS e Windows. O inverso também é validado pelos testes em `shared/dotnet/LionPass.Core.Tests`.
