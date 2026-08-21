# Lion Pass

Gerenciador de senhas local e offline da [Lion Code Technology](https://lioncodetech.com.br/), com aplicações para Apple, Windows e Linux no mesmo repositório.

## Plataformas

- [`apple/`](apple/README.md): iPhone, iPad e macOS 14+, em Swift e SwiftUI.
- [`windows/`](windows/README.md): Windows 10 19041+ e Windows 11, em .NET 8 e WinUI 3.
- [`linux/`](linux/README.md): Linux x64/ARM64, em .NET 8 e Avalonia.
- [`shared/`](shared/): núcleo C# compartilhado, identidade visual, contrato do formato e vetores de compatibilidade.

As três implementações usam o mesmo formato portátil `.lionvault`: PBKDF2-HMAC-SHA256, chave de conteúdo aleatória e AES-256-GCM autenticado. O cofre continua local; não há servidor, conta, analytics ou sincronização obrigatória.

## Estrutura

```text
apple/      Projetos Xcode, fontes Swift e testes Apple
windows/    Solução .NET, aplicação WinUI e integração Windows Hello/DPAPI
linux/      Aplicação Avalonia, integração Secret Service e pacotes Linux
shared/     Núcleo C#, testes, ícones, marca, especificação e fixtures sintéticas
docs/       Segurança, compatibilidade e publicação
.github/    Validação independente para Apple, Windows e Linux
```

## Segurança

Nunca envie cofres reais, senhas, chaves de recuperação, certificados ou pacotes assinados ao Git. A política de segurança e o modelo de ameaças estão em [`docs/security.md`](docs/security.md).

## Créditos

Criado por [Lion Code Technology](https://lioncodetech.com.br/).

© 2026 Lion Code Technology. Todos os direitos reservados.
