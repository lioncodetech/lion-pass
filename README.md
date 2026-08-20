# Lion Password

Gerenciador de senhas local/offline para iOS e iPadOS, escrito em SwiftUI. O cofre usa um formato próprio versionado (`.lionvault`), PBKDF2-HMAC-SHA256 para derivação de chave e AES-256-GCM para criptografia autenticada.

## Abrir e executar

1. Instale o Xcode 16 ou posterior e o XcodeGen (`brew install xcodegen`).
2. Execute `xcodegen generate` nesta pasta.
3. Abra `LionPassword.xcodeproj`, selecione o target **LionPassword** e execute em iOS 17+.
4. Para AutoFill, configure um Team e substitua `group.com.example.lionpassword` nos entitlements por um App Group próprio.

O app não usa rede, analytics ou backend. A extensão AutoFill é incluída como target separado. O cofre nunca é persistido descriptografado.

## Segurança

- AES-256-GCM via CryptoKit, nonce aleatório a cada gravação.
- PBKDF2-HMAC-SHA256 com salt aleatório e 600.000 iterações via CommonCrypto.
- Escrita atômica com última cópia criptografada válida.
- Senha mestra mantida apenas durante a operação necessária.
- Biometria protege no Keychain uma chave aleatória que envolve a chave derivada; não substitui a senha mestra.
- Clipboard é limpo apenas se ainda contiver o valor copiado.

Veja [THREAT_MODEL.md](THREAT_MODEL.md) para limites e decisões de segurança.

> PBKDF2 foi escolhido por estar disponível nativamente e ser uma KDF consolidada. Argon2id é recomendado para uma futura migração versionada após incorporar uma implementação auditada.

## Créditos

Criado por [Lion Code Technology](https://lioncodetech.com.br/).

© 2026 Lion Code Technology. Todos os direitos reservados.
