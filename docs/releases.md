# Publicações

Use uma única versão semântica para todas as plataformas, por exemplo `v2.0.0`. Uma publicação deve conter:

- `LionPass-2.0.0-macOS.dmg`;
- `LionPass-2.0.0-Windows-x64-Setup.exe`;
- `lion-pass_2.0.0_amd64.deb`;
- `LionPass-2.0.0-x86_64.AppImage`;
- `LionPass-Linux-linux-x64-2.0.0.tar.gz`;
- notas sobre alterações no formato `.lionvault`, quando existirem.

Builds de CI são artefatos de teste. Antes de distribuição pública, assine e faça notarização do aplicativo macOS, assine o instalador Windows e publique checksums/assinaturas dos pacotes Linux. Nunca inclua fixtures, cofres pessoais ou chaves nos pacotes finais.
