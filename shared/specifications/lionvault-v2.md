# Especificação Lion Vault v2

Este documento é o contrato de interoperabilidade entre Lion Pass para Apple e Windows.

## Envelope

O arquivo `.lionvault` é JSON UTF-8 com chaves em `camelCase`. Campos binários são Base64 padrão.

| Campo | Tipo | Regra |
|---|---|---|
| `magic` | string | `LIONVAULT` |
| `version` | inteiro | `2` |
| `kdf.algorithm` | string | `PBKDF2-HMAC-SHA256` |
| `kdf.iterations` | inteiro | padrão `600000`, aceito `100000...5000000` |
| `kdf.keyLength` | inteiro | `32` |
| `salt` | bytes | mínimo 16, escritor usa 32 |
| `keyNonce` | bytes | 12 |
| `wrappedKey` | bytes | chave de conteúdo de 32 bytes cifrada |
| `keyTag` | bytes | 16 |
| `nonce` | bytes | 12 |
| `ciphertext` | bytes | payload JSON cifrado |
| `tag` | bytes | 16 |

## Criptografia

1. Gere uma chave de conteúdo aleatória de 32 bytes.
2. Derive a chave da senha com PBKDF2-HMAC-SHA256 e o `salt` do envelope.
3. Proteja a chave de conteúdo com AES-256-GCM usando `keyNonce`.
4. Codifique o payload em JSON e proteja-o com AES-256-GCM usando `nonce`.
5. Não use AAD. Grave ciphertext e tag separadamente.

Versão 1 usa diretamente a chave derivada para cifrar o payload e permanece somente para leitura.

## Datas

Datas atuais são números em segundos desde `2001-01-01T00:00:00Z`, o formato `.deferredToDate` do Foundation. Leitores também aceitam o formato legado em milissegundos desde Unix quando o valor absoluto é maior que `10000000000`.

## Chave de recuperação

`LION-RECOVERY-` + Base64URL sem padding dos 32 bytes da chave de conteúdo seguidos dos primeiros 4 bytes de SHA-256 dessa chave.

## Evolução

Novos campos opcionais podem ser acrescentados ao payload. Mudanças criptográficas ou incompatíveis exigem uma nova versão do envelope. Nenhuma implementação deve reduzir iterações, reutilizar nonce ou gravar plaintext em logs.
