# Modelo de ameaças — Lion Pass

## Objetivos e limites

O Lion protege a confidencialidade e a integridade do cofre em repouso. Ele não promete proteger segredos em um aparelho comprometido por malware, jailbreak, depurador privilegiado ou durante o momento em que o próprio usuário os visualiza.

| Ameaça | Mitigação implementada | Risco residual |
|---|---|---|
| Roubo do arquivo | Payload cifrado com AES-256-GCM e chave aleatória de 256 bits | A senha mestra precisa continuar forte |
| Força bruta offline | PBKDF2-HMAC-SHA256, salt de 32 bytes e 600 mil iterações | Hardware futuro; migração versionada para Argon2id continua recomendada |
| Arquivo alterado ou truncado | Header/versionamento validado e autenticação GCM tanto da chave quanto do payload | Negação de serviço continua possível |
| Dispositivo bloqueado | Complete File Protection no iOS, Keychain `WhenUnlockedThisDeviceOnly`, DPAPI por usuário no Windows e bloqueio do app | Backups externos ainda dependem da senha ou da chave de recuperação |
| Dispositivo desbloqueado | Bloqueio automático e eliminação do payload/chave do estado ativo ao bloquear | Malware privilegiado pode observar memória ou interface |
| Clipboard | Cópia local, expiração configurável e limpeza condicional; padrão de 30 segundos | Outro app pode ler o clipboard antes da expiração, conforme as regras do sistema operacional |
| Screenshots, gravação e App Switcher | `privacySensitive`, capa no background e ocultação enquanto a tela é capturada | O iOS não oferece garantia geral contra captura iniciada pelo usuário |
| Backups e exportação | Somente o envelope autenticado e criptografado é exportado; última versão válida permanece cifrada | Uma cópia antiga pode continuar aceitando uma senha antiga |
| Logs e crash reports | Nenhum segredo é registrado e não há SDK de analytics/crash reporting | Logs do próprio sistema estão fora do controle total do app |
| Arquivos temporários | Escrita atômica com Data Protection, leitura de verificação e remoção do temporário; nunca há plaintext no disco | O sistema operacional gerencia os blocos físicos do armazenamento |
| AutoFill | App Group contém apenas o `.lionvault`; Identity Store recebe domínio, usuário e UUID, nunca senha; extensão autentica e limpa o estado após o uso | A extensão vê somente a credencial selecionada durante a solicitação |
| Biometria | Apple usa Keychain com `biometryCurrentSet`; Windows exige Windows Hello e protege a chave com DPAPI para o usuário atual; biometria é só conveniência | Herda as garantias do sensor, Keychain/DPAPI e credencial do dispositivo |
| Perda da senha mestra | Chave de recuperação local de alta entropia, com checksum, mostrada uma vez na criação | Se senha, chave de recuperação e biometria forem perdidas, não existe recuperação |

## Modelo criptográfico do formato v2

1. O app gera uma chave aleatória de conteúdo de 256 bits.
2. O payload é cifrado com essa chave por AES-256-GCM.
3. PBKDF2-HMAC-SHA256 deriva uma chave de proteção a partir da senha mestra e de um salt exclusivo.
4. A chave de conteúdo é envolvida por outro AES-GCM e armazenada no envelope.
5. Trocar a senha substitui apenas o envolvimento da chave, de forma atômica; a chave de recuperação permanece válida.
6. O leitor continua compatível com cofres v1 e os migra para v2 na troca da senha.

## Regras invariantes

1. Nunca registrar senha mestra, chave, payload, senha, nota ou credencial.
2. Nunca persistir payload descriptografado em Documents, Caches, tmp ou UserDefaults.
3. Nunca abrir conteúdo cuja autenticação GCM falhe.
4. Toda mudança gera um envelope autenticado novo, faz leitura de verificação e substitui o anterior atomicamente.
5. A versão anterior permanece cifrada e pode ser restaurada somente após autenticação.
6. A extensão AutoFill não mantém credenciais descriptografadas entre solicitações.
7. A chave de recuperação não é persistida em texto puro nem enviada para servidor.

## Evolução segura

- Introduzir Argon2id somente por uma nova versão de KDF e com implementação auditada.
- Adicionar testes de interface em dispositivos reais para Face ID/Touch ID, AutoFill e Data Protection.
- Reavaliar o custo da KDF periodicamente sem aceitar parâmetros externos ilimitados.
