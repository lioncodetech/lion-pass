# Modelo de ameaças — Lótus Password

## Objetivos e limites

O projeto protege a confidencialidade e a integridade de um cofre em repouso. Não promete proteger segredos em um aparelho já comprometido, com malware, jailbreak, depurador privilegiado ou enquanto o usuário os visualiza.

| Ameaça | Mitigação | Risco residual |
|---|---|---|
| Roubo do arquivo | AES-256-GCM e salt exclusivo | A força da senha mestra continua essencial |
| Força bruta offline | PBKDF2-HMAC-SHA256, 600 mil iterações | Hardware futuro; migrar para Argon2id auditado |
| Arquivo alterado/truncado | Tag GCM, validação de header e versão | Negação de serviço continua possível |
| Dispositivo bloqueado | Complete File Protection e bloqueio do app | Backups do arquivo continuam sujeitos à senha |
| Dispositivo desbloqueado | Bloqueio automático e dados apenas em memória | Malware com privilégios pode observar memória/UI |
| Clipboard | Expiração local e limpeza condicional em 30 s por padrão | Outros apps podem ler antes da limpeza conforme política do iOS |
| Screenshots/App Switcher | `privacySensitive` e bloqueio em background | iOS não oferece garantia geral contra captura pelo usuário |
| Backups/exportação | Somente o envelope criptografado é exportado | Cópias antigas aceitam a senha antiga |
| Logs/crash reports | Nenhum segredo é registrado; sem SDK de analytics | Logs do sistema estão fora do controle total do app |
| Arquivos temporários | Escrita com proteção completa; nenhum plaintext em disco | O sistema operacional gerencia blocos físicos |
| AutoFill | Extensão exige desbloqueio e limpa itens após uso; App Group contém só o cofre cifrado | Processo da extensão vê a credencial selecionada durante a operação |
| Biometria | Conveniência via LocalAuthentication; falhas não liberam o cofre | Biometria herda as garantias do aparelho e deve envolver chave no Keychain antes de ser habilitada |

## Regras invariantes

1. Nunca registrar senha mestra, chave, payload, senha, nota ou credencial.
2. Nunca persistir payload descriptografado em Documents, Caches, tmp ou UserDefaults.
3. Nunca abrir conteúdo cuja autenticação GCM falhe.
4. Toda mudança produz um envelope novo, validado por leitura e substituído atomicamente; a versão anterior permanece cifrada.
5. A extensão AutoFill não mantém credenciais entre solicitações.

## Evolução recomendada

- Introduzir Argon2id por nova versão de envelope, sem rebaixamento silencioso.
- Implementar chave de recuperação opcional como segundo slot de envolvimento de chave.
- Envolver a chave derivada com chave aleatória protegida por `kSecAccessControlBiometryCurrentSet` para habilitar desbloqueio biométrico persistente.
- Testar interrupção real de I/O, vetores NIST AES-GCM e fluxos de LocalAuthentication em dispositivo.
