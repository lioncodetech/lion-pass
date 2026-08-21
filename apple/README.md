# Lion Pass para Apple

Aplicações nativas para iPhone, iPad e macOS, escritas com SwiftUI.

## Gerar e executar

1. Instale Xcode 16 ou mais recente e XcodeGen (`brew install xcodegen`).
2. Nesta pasta, execute `xcodegen generate`.
3. Abra `LionPass.xcodeproj`.
4. Execute **LionPass** em iOS/iPadOS 17+ ou **LionPassMac** no macOS 14+.

No iOS, habilite Lion Pass em Ajustes → Geral → Preenchimento Automático e Senhas. App Groups e a extensão AutoFill precisam existir no perfil de assinatura usado em dispositivo físico.

## Testes

```bash
./scripts/test-macos.sh
```

O script usa `apple/.derived-data.noindex`, remove o registro da build de teste no Launch Services e apaga o pacote `.app` temporário ao terminar. Não gere builds do Lion Pass em `/tmp` ou `/private/tmp`: o Spotlight pode interpretá-las como outras instalações do aplicativo.

O formato do cofre é documentado em [`../shared/specifications/lionvault-v2.md`](../shared/specifications/lionvault-v2.md).
