# Publicações

Use uma única versão semântica para todas as plataformas, por exemplo `v2.0.0`. O workflow [`release.yml`](../.github/workflows/release.yml) valida a tag, exige que ela pertença à branch `main`, compila as três plataformas e cria o GitHub Release automaticamente.

```bash
git switch main
git pull --ff-only
git tag -a v2.0.0 -m "Lion Pass 2.0.0"
git push origin v2.0.0
```

Uma publicação contém:

- `LionPass-2.0.0-macOS-unsigned.dmg`;
- `LionPass-Windows-x64-2.0.0-Setup.exe`;
- `lion-pass_2.0.0_amd64.deb`;
- `LionPass-2.0.0-x86_64.AppImage`;
- `LionPass-Linux-linux-x64-2.0.0.tar.gz`;
- notas sobre alterações no formato `.lionvault`, quando existirem.

Todos os pacotes, o `SHA256SUMS` e seus bundles recebem assinatura Sigstore antes da publicação. Sem credenciais Apple Developer, o DMG é explicitamente publicado como `unsigned` e pode acionar o Gatekeeper. Antes de uma distribuição pública confiável, configure assinatura e notarização Apple. Nunca inclua fixtures, cofres pessoais ou chaves nos pacotes finais.

Não recrie nem mova uma tag publicada. Para corrigir uma versão, faça um novo patch, como `v2.0.1`.

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

Para um GitHub Release, use `release.yml` e a referência da própria tag, por exemplo `refs/tags/v2.0.0`, na identidade do certificado.

Para que o instalador Windows também mostre a Lion Code Technology como publicadora no diálogo nativo do Windows, configure estes secrets do repositório:

- `WINDOWS_SIGNING_CERTIFICATE_BASE64`: certificado Authenticode `.pfx` codificado em Base64;
- `WINDOWS_SIGNING_CERTIFICATE_PASSWORD`: senha do certificado.

O certificado é disponibilizado somente ao job isolado de assinatura, somente em pushes confiáveis, gravado temporariamente no runner e removido ao final. Sem esses secrets, o pipeline continua exigindo e verificando a assinatura Sigstore, mas o Windows poderá exibir “publicador desconhecido”.
