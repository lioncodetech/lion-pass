# Publicações

Use uma única versão semântica para todas as plataformas, por exemplo `v2.0.0`. Uma publicação deve conter:

- `LionPass-2.0.0-macOS.dmg`;
- `LionPass-2.0.0-Windows-x64-Setup.exe`;
- `lion-pass_2.0.0_amd64.deb`;
- `LionPass-2.0.0-x86_64.AppImage`;
- `LionPass-Linux-linux-x64-2.0.0.tar.gz`;
- notas sobre alterações no formato `.lionvault`, quando existirem.

Builds de CI são artefatos de teste. Antes de distribuição pública, assine e faça notarização do aplicativo macOS, assine o instalador Windows e publique checksums/assinaturas dos pacotes Linux. Nunca inclua fixtures, cofres pessoais ou chaves nos pacotes finais.

## Verificação dos artefatos de CI

Os workflows Windows e Linux publicam, em pushes confiáveis, um arquivo `SHA256SUMS` e um bundle Sigstore `*.sigstore.json` para cada instalador/pacote. Verifique primeiro o checksum e depois a identidade do workflow:

```bash
sha256sum --check SHA256SUMS
cosign verify-blob ARQUIVO \
  --bundle ARQUIVO.sigstore.json \
  --certificate-identity "https://github.com/lioncodetech/lion-pass/.github/workflows/WORKFLOW.yml@refs/heads/main" \
  --certificate-oidc-issuer "https://token.actions.githubusercontent.com"
```

Use `windows-build.yml` ou `linux-build.yml` no lugar de `WORKFLOW.yml`. A assinatura Sigstore é obrigatória no pipeline e vincula o binário ao workflow e commit que o geraram.

Para que o instalador Windows também mostre a Lion Code Technology como publicadora no diálogo nativo do Windows, configure estes secrets do repositório:

- `WINDOWS_SIGNING_CERTIFICATE_BASE64`: certificado Authenticode `.pfx` codificado em Base64;
- `WINDOWS_SIGNING_CERTIFICATE_PASSWORD`: senha do certificado.

O certificado é disponibilizado somente ao job isolado de assinatura, somente em pushes confiáveis, gravado temporariamente no runner e removido ao final. Sem esses secrets, o pipeline continua exigindo e verificando a assinatura Sigstore, mas o Windows poderá exibir “publicador desconhecido”.
