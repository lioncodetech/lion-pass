# Lion Pass

Gerenciador de senhas local e offline para iPhone, iPad e Mac, escrito com SwiftUI. O cofre portátil usa o formato próprio `.lionvault`, PBKDF2-HMAC-SHA256 e AES-256-GCM autenticado. Não há servidor, conta, analytics ou dependência de iCloud.

## Recursos

- logins, cartões, notas seguras, identidades, favoritos, tags e campos personalizados;
- categorias padrão e personalizadas;
- pesquisa no iPhone e `NavigationSplitView` no iPad;
- histórico opcional de senhas;
- geradores criptograficamente seguros de senha e frase-senha;
- Face ID/Touch ID com chave protegida no Keychain;
- chave de recuperação local mostrada uma vez;
- bloqueio automático, capa de privacidade e clipboard configurável;
- importação, exportação, verificação e restauração do último cofre cifrado válido;
- extensão Password AutoFill, App Group e sugestões pelo Credential Identity Store;
- temas Sistema, Claro e Escuro;
- formato v1 legível e formato v2 atual.

## Gerar e executar

1. Instale Xcode 16 ou mais recente e XcodeGen (`brew install xcodegen`).
2. Execute `xcodegen generate` nesta pasta.
3. Abra `LionPass.xcodeproj`.
4. Selecione sua equipe de desenvolvimento e execute **LionPass** em iOS/iPadOS 17+ ou **LionPassMac** no macOS 14+.
5. No iOS, habilite Lion Pass em Ajustes → Geral → Preenchimento Automático e Senhas.

O projeto usa os identificadores `com.lioncodetech.lionpassword` e `group.com.lioncodetech.lionpassword`. App Groups e a extensão AutoFill precisam existir no perfil de assinatura usado para instalar em dispositivo físico.

## Segurança

O formato v2 gera uma chave aleatória de conteúdo para o payload e protege essa chave separadamente com a senha mestra. Isso permite trocar a senha sem invalidar a chave de recuperação. Parâmetros KDF externos são limitados antes da derivação para evitar abuso de recursos.

PBKDF2 foi escolhido por estar disponível nativamente e ser uma KDF consolidada. Uma futura migração para Argon2id deve ser versionada e usar uma implementação auditada.

Veja [THREAT_MODEL.md](THREAT_MODEL.md) para ameaças, limites e decisões de segurança.

## Créditos

Criado por [Lion Code Technology](https://lioncodetech.com.br/).

© 2026 Lion Code Technology. Todos os direitos reservados.
